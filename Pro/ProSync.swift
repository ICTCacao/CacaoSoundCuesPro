import AppKit
import CacaoSoundCuesCore
import CryptoKit
import Network
import SwiftUI

// バックアップ機との同時運転（Pro 版）。
// メイン機の操作（鳴らす・止める・Standby を動かす…）を、そのままバックアップ機へ送り、バックアップ機も同じように鳴らす。
// 音は送らない。2 台とも自分の機器から鳴らし、ミキサーで人が切り替える。
// つなぎ方: 同じネットワーク。メイン機が待ち受け（Bonjour で名乗る。IP でもつなげる）、バックアップ機がつなぐ。
// 初めての相手とは、メイン機に出る 4 桁のペアKeyで組にする（次からは覚えている）。
// 引き継ぐと世代（generation）が上がる。メイン機どうしが出会ったら、世代の古い方がバックアップになる（役の入れ替え）

/// 送る操作（どれも AppModel の操作の入口と同じ。キーではなく「何をしたか」を送るので、画面の選び方でずれない）
enum SyncOp: Codable, Equatable {
    case trigger(UUID)
    case panic
    case toggleSequence(UUID)
    case cueStep(UUID, Int)
    case startSequence(UUID, Int)
    case stopSequence(UUID)
    case advance
    case endSong
    case masterVolume(Double)
    case stopMark(UUID)
    case page(Int)
    /// 台本をスクロールで流した位置（ページ単位）
    case scroll(Double)
}

/// やりとりする知らせ
enum SyncMessage: Codable {
    struct Hello: Codable {
        var id: String
        var name: String
        /// "main" か "backup"
        var role: String
        var generation: Int
        var code: String?
        var version: String
    }
    struct FileEntry: Codable {
        var path: String
        var size: Int
    }
    case hello(Hello)
    /// つないでよいか。demote が true なら、相手（つないできた方）がバックアップになる
    case welcome(ok: Bool, reason: String?, name: String, id: String, generation: Int, demote: Bool)
    case op(SyncOp)
    case ping(Double)
    case pong(Double)
    /// キューシートの名前と中身の印（同じか確かめる）
    case sheet(name: String, hash: String, dirty: Bool)
    case requestSheet
    case fileStart(name: String, files: [FileEntry])
    case fileChunk(index: Int, data: Data)
    case fileEnd
    /// バックアップ機が引き継いだ（受けたメイン機はバックアップになる）
    case takeover(generation: Int)
}

@MainActor @Observable
final class ProSync {
    static let shared = ProSync()
    static let serviceType = "_cacaosc._tcp"
    static let port: NWEndpoint.Port = 52710

    enum Role: String { case off, main, backup }

    // MARK: 状態（画面に出す）

    private(set) var role: Role
    /// 相手とつながっているか（組になって合図が届いている）
    private(set) var connected = false
    private(set) var peerName = ""
    private(set) var latencyMs: Double?
    /// 相手のキューシートの名前と印（同じか確かめる）
    private(set) var peerSheet: (name: String, hash: String, dirty: Bool)?
    private(set) var mySheetHash = ""
    /// メイン機に出す、組にするためのペアKey
    private(set) var code = String(format: "%04d", Int.random(in: 0...9999))
    /// バックアップ機で見つかったメイン機
    private(set) var found: [NWBrowser.Result] = []
    /// 最後の知らせ（画面の下に出す）
    private(set) var status = ""
    /// キューシートを受け取っている途中（0〜1）
    private(set) var receiving: Double?
    /// 一度つながったあと、切れている（バックアップ機は大きく知らせる）
    private(set) var lost = false

    private(set) var generation: Int {
        didSet { UserDefaults.standard.set(generation, forKey: "pro.sync.generation") }
    }
    private let myID: String
    private var paired: Set<String> {
        didSet { UserDefaults.standard.set(Array(paired), forKey: "pro.sync.paired") }
    }

    // MARK: つなぎ

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    /// つないだ相手の場所（切れたらつなぎ直す）
    private var target: NWEndpoint?
    private var targetCode: String?
    private var lastHeard = Date.distantPast
    private var timer: Timer?
    private var buffer = Data()
    /// 受け取り中のキューシート
    private var incoming: (name: String, files: [SyncMessage.FileEntry], folder: URL, index: Int, written: Int, total: Int)?

    // MARK: 操作の送り・止め

    /// 相手から届いた操作を実行している最中
    private var remote = false
    /// 操作の入れ子の深さ（中から呼ばれた操作は送らない）
    private var depth = 0

    private init() {
        role = Role(rawValue: UserDefaults.standard.string(forKey: "pro.sync.role") ?? "") ?? .off
        generation = UserDefaults.standard.integer(forKey: "pro.sync.generation")
        if let id = UserDefaults.standard.string(forKey: "pro.sync.id") {
            myID = id
        } else {
            myID = UUID().uuidString
            UserDefaults.standard.set(myID, forKey: "pro.sync.id")
        }
        paired = Set(UserDefaults.standard.stringArray(forKey: "pro.sync.paired") ?? [])
    }

    /// 起動したとき
    func startUp() {
        setRole(role, force: true)
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    var myName: String { Host.current().localizedName ?? "Mac" }

    /// 操作の入口で呼ぶ。false なら、その操作をしない（バックアップ機の手の操作）
    func begin(_ op: SyncOp) -> Bool {
        if remote {
            depth += 1
            return true
        }
        if role == .backup {
            switch op {
            // 全体の音量（出力をやり直したときにも当て直す）と Esc（万一のとき）は、バックアップ機でも効かせる
            case .masterVolume, .panic:
                depth += 1
                return true
            default:
                status = L("バックアップ機です。操作はメイン機で（このMacで操作するときは「引き継ぐ」）")
                NSSound.beep()
                return false
            }
        }
        if role == .main, depth == 0 { send(.op(op)) }
        depth += 1
        return true
    }

    func end() { depth = max(0, depth - 1) }

    /// 台本のページを送ったとき（メイン機だけ送る）
    func pageChanged(_ page: Int) {
        guard role == .main, !remote, connected else { return }
        send(.op(.page(page)))
    }

    /// 台本をスクロールで流したとき（メイン機だけ送る。1 秒に 30 回ほどにまとめ、止めた位置は必ず送る）
    func scrolled(_ pos: Double) {
        guard role == .main, !remote, connected else { return }
        pendingScroll = pos
        guard scrollWork == nil else { return }
        let wait = max(0, 0.033 - Date().timeIntervalSince(lastScrollSent))
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.scrollWork = nil
                if let p = self.pendingScroll {
                    self.pendingScroll = nil
                    self.lastScrollSent = Date()
                    self.send(.op(.scroll(p)))
                }
            }
        }
        scrollWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }
    private var pendingScroll: Double?
    private var scrollWork: DispatchWorkItem?
    private var lastScrollSent = Date.distantPast

    private func apply(_ op: SyncOp) {
        let m = AppModel.shared
        remote = true
        defer { remote = false }
        switch op {
        case .trigger(let id):
            if let cue = m.show.keyCues.first(where: { $0.id == id }) { m.trigger(cue) }
        case .panic: m.panic()
        case .toggleSequence(let id): m.toggleSequence(id)
        case .cueStep(let id, let i): m.cueStep(id, index: i)
        case .startSequence(let id, let i): m.startSequence(id, from: i)
        case .stopSequence(let id): m.stopSequence(id)
        case .advance: m.advanceActiveSequence()
        case .endSong: m.endCurrentSequenceSong()
        case .masterVolume(let db):
            if m.show.masterVolumeDB != db { m.show.masterVolumeDB = db }
            m.applyMasterVolume()
        case .stopMark(let id): ProModel.shared.stop(markID: id)
        case .page(let p): ProModel.shared.page = p
        case .scroll(let pos): ProModel.shared.scrollRequest = pos
        }
    }

    // MARK: 役

    func setRole(_ r: Role, force: Bool = false) {
        guard force || r != role else { return }
        role = r
        UserDefaults.standard.set(r.rawValue, forKey: "pro.sync.role")
        disconnect()
        listener?.cancel(); listener = nil
        browser?.cancel(); browser = nil
        target = nil
        lost = false
        status = ""
        switch r {
        case .off: break
        case .main:
            startListener()
            startBrowser()   // ほかのメイン機（引き継いだ機）を見つけるため
        case .backup:
            startBrowser()
        }
    }

    /// バックアップ機を、このMacで操作できるようにする（メイン機になる）
    func takeOver() {
        generation += 1
        let gen = generation
        // まだつながっていれば、相手にバックアップになってもらう
        if connected { send(.takeover(generation: gen)) }
        setRole(.main)
        status = L("引き継ぎました。このMacがメイン機です")
    }

    // MARK: メイン機: 待ち受け

    private func startListener() {
        let params = NWParameters.tcp
        params.includePeerToPeer = false
        let l = (try? NWListener(using: params, on: Self.port)) ?? (try? NWListener(using: params))
        guard let l else {
            status = L("待ち受けを始められません")
            return
        }
        l.service = NWListener.Service(name: myName, type: Self.serviceType)
        l.newConnectionHandler = { [weak self] conn in
            MainActor.assumeIsolated { self?.accept(conn) }
        }
        l.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                if case .failed(let e) = state { self?.status = L("待ち受けできません: %@", e.localizedDescription) }
            }
        }
        l.start(queue: .main)
        listener = l
    }

    private func accept(_ conn: NWConnection) {
        // 相手は 1 台だけ。つながっている間は、新しい方を断る
        if connected {
            conn.cancel()
            return
        }
        disconnect()
        use(conn)
    }

    // MARK: バックアップ機: さがす・つなぐ

    private func startBrowser() {
        let b = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated { self?.foundChanged(Array(results)) }
        }
        b.start(queue: .main)
        browser = b
    }

    private func foundChanged(_ results: [NWBrowser.Result]) {
        found = results.filter { name(of: $0) != myName }
        // メイン機は、ほかのメイン機を見つけたら確かめにいく（世代の古い方がバックアップになる）
        if role == .main, !connected, let other = found.first {
            target = other.endpoint
            connect(other.endpoint)
        }
    }

    func name(of r: NWBrowser.Result) -> String {
        if case .service(let name, _, _, _) = r.endpoint { return name }
        return "\(r.endpoint)"
    }

    /// バックアップ機から、メイン機につなぐ（code は初めての相手のとき）
    func connect(to endpoint: NWEndpoint, code: String?) {
        target = endpoint
        targetCode = code
        connect(endpoint)
    }

    func connect(host: String, code: String?) {
        connect(to: .hostPort(host: NWEndpoint.Host(host), port: Self.port), code: code)
    }

    private func connect(_ endpoint: NWEndpoint) {
        disconnect()
        let conn = NWConnection(to: endpoint, using: .tcp)
        use(conn)
        send(.hello(.init(id: myID, name: myName, role: role.rawValue, generation: generation,
                          code: targetCode, version: AppModel.versionText)))
    }

    private func use(_ conn: NWConnection) {
        connection = conn
        buffer = Data()
        conn.stateUpdateHandler = { [weak self, weak conn] state in
            MainActor.assumeIsolated {
                guard let self, let conn, conn === self.connection else { return }
                switch state {
                case .failed, .cancelled: self.dropped()
                default: break
                }
            }
        }
        conn.start(queue: .main)
        receive(conn)
    }

    private func disconnect() {
        connection?.cancel()
        connection = nil
        if connected { lost = true }
        connected = false
        latencyMs = nil
        peerSheet = nil
    }

    private func dropped() {
        if connected {
            lost = true
            status = role == .backup ? L("メイン機と切れました") : L("バックアップ機と切れました")
        }
        connection = nil
        connected = false
        latencyMs = nil
    }

    // MARK: 合図

    private func tick() {
        guard role != .off else { return }
        if connected {
            send(.ping(Date().timeIntervalSince1970))
            if Date().timeIntervalSince(lastHeard) > 2 {
                // 2 秒届かなければ切れたとみなす
                disconnect()
                status = role == .backup ? L("メイン機と切れました") : L("バックアップ機と切れました")
            }
        } else if role == .backup, let target, connection == nil {
            // バックアップ機は、切れたらつなぎ直す
            connect(target)
        }
        let h = currentSheetHash()
        if h != mySheetHash {
            mySheetHash = h
            if connected { sendSheet() }
        }
    }

    // MARK: 送る・受ける（4 バイトの長さ ＋ JSON）

    private func send(_ m: SyncMessage) {
        guard let conn = connection, let body = try? JSONEncoder().encode(m) else { return }
        var len = UInt32(body.count).bigEndian
        var data = Data(bytes: &len, count: 4)
        data.append(body)
        conn.send(content: data, completion: .contentProcessed { _ in })
    }

    private func receive(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self, weak conn] data, _, done, error in
            MainActor.assumeIsolated {
                guard let self, let conn, conn === self.connection else { return }
                if let data { self.buffer.append(data) }
                self.drain()
                if done || error != nil {
                    self.dropped()
                } else {
                    self.receive(conn)
                }
            }
        }
    }

    private func drain() {
        while buffer.count >= 4 {
            let len = buffer.prefix(4).reduce(0) { $0 << 8 | Int($1) }
            guard buffer.count >= 4 + len else { return }
            let body = buffer.subdata(in: buffer.startIndex + 4 ..< buffer.startIndex + 4 + len)
            buffer.removeSubrange(buffer.startIndex ..< buffer.startIndex + 4 + len)
            buffer = Data(buffer)
            if let m = try? JSONDecoder().decode(SyncMessage.self, from: body) { handle(m) }
        }
    }

    private func handle(_ m: SyncMessage) {
        lastHeard = Date()
        switch m {
        case .hello(let h):
            // メイン機: 組の相手か、ペアKeyが合えばつなぐ
            let known = paired.contains(h.id)
            guard known || h.code == code else {
                send(.welcome(ok: false, reason: L("ペアKeyが違います"), name: myName, id: myID, generation: generation, demote: false))
                status = L("「%@」が違うペアKeyでつなごうとしました", h.name)
                return
            }
            paired.insert(h.id)
            // 相手もメイン機なら、世代の古い方がバックアップになる
            var demoteThem = true
            if h.role == "main", h.generation > generation {
                demoteThem = false
            }
            send(.welcome(ok: true, reason: nil, name: myName, id: myID, generation: generation, demote: demoteThem))
            peerName = h.name
            connected = true
            lost = false
            if !demoteThem { becomeBackup(keeping: true) }
            status = L("「%@」とつながりました", h.name)
            sendSheet()
        case .welcome(let ok, let reason, let name, let id, let gen, let demote):
            guard ok else {
                status = L("つなげません: %@", reason ?? "")
                disconnect()
                target = nil
                return
            }
            paired.insert(id)
            peerName = name
            connected = true
            lost = false
            generation = max(generation, gen)
            if demote, role == .main { becomeBackup(keeping: true) }
            status = L("「%@」とつながりました", name)
            sendSheet()
        case .op(let op):
            // 操作を受けるのはバックアップ機だけ
            if role == .backup { apply(op) }
        case .ping(let t):
            send(.pong(t))
        case .pong(let t):
            latencyMs = (Date().timeIntervalSince1970 - t) * 1000 / 2
        case .sheet(let name, let hash, let dirty):
            peerSheet = (name, hash, dirty)
        case .requestSheet:
            sendWholeSheet()
        case .fileStart(let name, let files):
            startReceiving(name, files)
        case .fileChunk(let index, let data):
            receiveChunk(index, data)
        case .fileEnd:
            finishReceiving()
        case .takeover(let gen):
            // 相手が引き継いだ。こちらはバックアップになる
            generation = max(generation, gen)
            becomeBackup(keeping: true)
            status = L("「%@」が引き継ぎました。このMacはバックアップ機です", peerName)
        }
    }

    /// バックアップ機になる。keeping: いまのつながりはそのまま使う
    private func becomeBackup(keeping: Bool) {
        role = .backup
        UserDefaults.standard.set(Role.backup.rawValue, forKey: "pro.sync.role")
        listener?.cancel()
        listener = nil
        if !keeping { disconnect() }
        if case .some = connection?.endpoint as NWEndpoint? { target = connection?.endpoint }
        if browser == nil { startBrowser() }
    }

    // MARK: キューシートが同じか

    /// キューシートの中身の印（ファイルの場所と大きさ、設定のファイルは中身も）
    private func currentSheetHash() -> String {
        guard let url = AppModel.shared.showURL else { return "" }
        var h = SHA256()
        let fm = FileManager.default
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return "" }
        var entries: [(String, Int, URL)] = []
        for case let f as URL in e {
            let v = try? f.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard v?.isRegularFile == true else { continue }
            let rel = String(f.path.dropFirst(url.path.count))
            if rel.hasSuffix(".DS_Store") { continue }
            entries.append((rel, v?.fileSize ?? 0, f))
        }
        for (rel, size, f) in entries.sorted(by: { $0.0 < $1.0 }) {
            h.update(data: Data("\(rel):\(size)".utf8))
            if rel.hasSuffix(".json"), let d = try? Data(contentsOf: f) { h.update(data: d) }
        }
        return h.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func sendSheet() {
        let m = AppModel.shared
        send(.sheet(name: m.showURL?.deletingPathExtension().lastPathComponent ?? m.show.name,
                    hash: mySheetHash, dirty: m.dirty))
    }

    /// 2 台のキューシートが同じか（相手が分からなければ nil）
    var sheetsMatch: Bool? {
        guard let p = peerSheet, !mySheetHash.isEmpty else { return nil }
        return p.hash == mySheetHash && !p.dirty && !AppModel.shared.dirty
    }

    // MARK: キューシートを送る（メイン機 → バックアップ機）

    /// バックアップ機から、メイン機のキューシートを送ってもらう
    func requestSheet() {
        guard connected, role == .backup else { return }
        send(.requestSheet)
        status = L("メイン機にキューシートを頼みました")
    }

    /// メイン機から、バックアップ機へキューシートを送る
    func pushSheet() {
        guard connected, role == .main else { return }
        sendWholeSheet()
    }

    private func sendWholeSheet() {
        let m = AppModel.shared
        guard let url = m.showURL else {
            status = L("キューシートを保存してから送ってください")
            return
        }
        if m.dirty { status = L("未保存の変更は送られません（保存してから送ってください）") }
        let fm = FileManager.default
        var files: [(SyncMessage.FileEntry, URL)] = []
        if let e = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) {
            for case let f as URL in e {
                let v = try? f.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard v?.isRegularFile == true, !f.lastPathComponent.hasPrefix(".") else { continue }
                files.append((.init(path: String(f.path.dropFirst(url.path.count + 1)), size: v?.fileSize ?? 0), f))
            }
        }
        send(.fileStart(name: url.lastPathComponent, files: files.map(\.0)))
        let chunk = 256 * 1024
        for (i, (_, f)) in files.enumerated() {
            guard let h = try? FileHandle(forReadingFrom: f) else { continue }
            while let d = try? h.read(upToCount: chunk), !d.isEmpty {
                send(.fileChunk(index: i, data: d))
            }
            try? h.close()
        }
        send(.fileEnd)
        status = L("キューシート「%@」を送りました（%d 個のファイル）", url.deletingPathExtension().lastPathComponent, files.count)
    }

    /// 受け取ったキューシートを置く場所
    static var inbox: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("CacaoSoundCuesPro/FromMain", isDirectory: true)
    }

    private func startReceiving(_ name: String, _ files: [SyncMessage.FileEntry]) {
        let folder = Self.inbox.appendingPathComponent(".receiving-" + name, isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        incoming = (name, files, folder, -1, 0, max(1, files.reduce(0) { $0 + $1.size }))
        receiving = 0
        status = L("キューシート「%@」を受け取っています…", name)
    }

    private func receiveChunk(_ index: Int, _ data: Data) {
        guard var inc = incoming, inc.files.indices.contains(index) else { return }
        let url = inc.folder.appendingPathComponent(inc.files[index].path)
        let fm = FileManager.default
        if index != inc.index {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: url.path, contents: nil)
            inc.index = index
        }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        }
        inc.written += data.count
        incoming = inc
        receiving = Double(inc.written) / Double(inc.total)
    }

    private func finishReceiving() {
        guard let inc = incoming else { return }
        incoming = nil
        receiving = nil
        let fm = FileManager.default
        // 空のファイル（大きさ 0）も作っておく
        for f in inc.files where f.size == 0 {
            let url = inc.folder.appendingPathComponent(f.path)
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        }
        let dest = Self.inbox.appendingPathComponent(inc.name, isDirectory: true)
        try? fm.removeItem(at: dest)
        do {
            try fm.moveItem(at: inc.folder, to: dest)
        } catch {
            status = L("受け取ったキューシートを置けません: %@", error.localizedDescription)
            return
        }
        AppModel.shared.open(dest, evenInShowMode: true)
        status = L("メイン機のキューシート「%@」を開きました", dest.deletingPathExtension().lastPathComponent)
        mySheetHash = currentSheetHash()
        sendSheet()
    }
}

// MARK: - 画面

/// 上の帯の「同時運転」ボタン（つながりの色の印つき）
struct SyncTopBarButton: View {
    @State private var show = false
    private var sync: ProSync { ProSync.shared }

    var body: some View {
        // 狭いときは丸の印だけ（上の帯がラベルを絵だけにする）
        Button { show = true } label: {
            Label {
                Text(label)
            } icon: {
                Image(systemName: "circle.fill").foregroundStyle(color).imageScale(.small)
            }
        }
        .help(L("バックアップ機との同時運転（%@）", label))
        .sheet(isPresented: $show) { SyncSheet() }
        #if DEBUG
        // 開発版だけ: マニュアルの画面写真用に、起動引数で同時運転の画面を開く（-debugSync YES）
        .onAppear { if UserDefaults.standard.bool(forKey: "debugSync") { show = true } }
        #endif
    }

    private var label: String {
        switch sync.role {
        case .off: return L("同時運転")
        case .main: return L("メイン機")
        case .backup: return L("バックアップ機")
        }
    }

    private var color: Color {
        if sync.role == .off { return .gray }
        if !sync.connected { return .red }
        return sync.sheetsMatch == false ? .orange : .green
    }
}

/// バックアップ機で、つながっていない・メインと切れたときに大きく出す帯
struct SyncBanner: View {
    private var sync: ProSync { ProSync.shared }

    var body: some View {
        if sync.role == .backup {
            HStack(spacing: 10) {
                if sync.connected {
                    Image(systemName: "dot.radiowaves.left.and.right")
                    Text(L("バックアップ機: メイン機「%@」の操作どおりに鳴らしています（このMacの操作は効きません）", sync.peerName))
                    if sync.sheetsMatch == false {
                        Text(L("キューシートがメイン機と違います")).bold().foregroundStyle(.yellow)
                    }
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(sync.lost ? L("メイン機と切れました") : L("メイン機につながっていません")).bold()
                }
                Spacer()
                Button(L("引き継ぐ（このMacで操作する）")) { sync.takeOver() }
            }
            .font(sync.connected ? .callout : .title3)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, sync.connected ? 4 : 10)
            .background(sync.connected ? Color.blue.opacity(0.8) : Color.red)
        }
    }
}

/// 同時運転の設定
struct SyncSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var code = ""
    private var sync: ProSync { ProSync.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("バックアップ機との同時運転")).font(.title3.bold())
            Text(L("メイン機の操作を、バックアップ機へそのまま送り、2 台で同じように鳴らします（音は送りません）。2 台の出力をミキサーの別々の入力に入れ、ふだんはメイン機だけを上げてください。同じネットワーク（有線 LAN をおすすめ）につないでください。"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker(L("このMac"), selection: Binding(get: { sync.role }, set: { sync.setRole($0) })) {
                Text(L("使わない")).tag(ProSync.Role.off)
                Text(L("メイン機")).tag(ProSync.Role.main)
                Text(L("バックアップ機")).tag(ProSync.Role.backup)
            }
            .pickerStyle(.segmented)

            switch sync.role {
            case .off: EmptyView()
            case .main: mainPane
            case .backup: backupPane
            }

            if let p = sync.receiving {
                ProgressView(value: p) { Text(L("キューシートを受け取っています")) }
            }
            if !sync.status.isEmpty {
                Text(sync.status).font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button(L("閉じる")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private var connectionRow: some View {
        HStack(spacing: 8) {
            Circle().fill(sync.connected ? Color.green : Color.red).frame(width: 10, height: 10)
            if sync.connected {
                Text(L("「%@」とつながっています", sync.peerName))
                if let l = sync.latencyMs { Text(String(format: L("遅れ %.1f ms"), l)).foregroundStyle(.secondary).monospacedDigit() }
            } else {
                Text(L("つながっていません"))
            }
            Spacer()
        }
    }

    private var sheetRow: some View {
        HStack(spacing: 8) {
            switch sync.sheetsMatch {
            case .some(true):
                Label(L("キューシートは同じです"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .some(false):
                Label(L("キューシートが違います（未保存の変更も含む）"), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .none:
                Label(L("キューシートを照らし合わせられません"), systemImage: "questionmark.circle").foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var mainPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("ペアKey"))
                Text(sync.code).font(.title2.monospacedDigit().bold())
                Text(L("（初めてのバックアップ機に入れてもらう）")).font(.caption).foregroundStyle(.secondary)
            }
            Text(L("このMac「%@」で待ち受けています（ポート %d）", sync.myName, Int(ProSync.port.rawValue)))
                .font(.caption).foregroundStyle(.secondary)
            connectionRow
            if sync.connected {
                sheetRow
                Button { sync.pushSheet() } label: { Label(L("バックアップ機へキューシートを送る"), systemImage: "arrow.up.doc") }
            }
        }
    }

    private var backupPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            connectionRow
            if sync.connected {
                sheetRow
                HStack {
                    Button { sync.requestSheet() } label: { Label(L("メイン機のキューシートをもらう"), systemImage: "arrow.down.doc") }
                    Spacer()
                    Button(L("引き継ぐ（このMacで操作する）")) { sync.takeOver() }
                }
            } else {
                Text(L("メイン機")).font(.caption.bold())
                if sync.found.isEmpty {
                    Text(L("見つかりません。メイン機で「メイン機」を選び、同じネットワークにつないでください")).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(sync.found, id: \.endpoint) { r in
                    HStack {
                        Text(sync.name(of: r))
                        Spacer()
                        Button(L("つなぐ")) { sync.connect(to: r.endpoint, code: code.isEmpty ? nil : code) }
                    }
                }
                HStack {
                    TextField(L("IP アドレスでつなぐ（例 192.168.0.10）"), text: $host).textFieldStyle(.roundedBorder)
                    Button(L("つなぐ")) { sync.connect(host: host, code: code.isEmpty ? nil : code) }
                        .disabled(host.isEmpty)
                }
                HStack {
                    Text(L("ペアKey"))
                    TextField("0000", text: $code).textFieldStyle(.roundedBorder).frame(width: 80)
                    Text(L("（初めてのメイン機のとき。メイン機の画面に出ています）")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

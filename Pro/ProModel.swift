import AppKit
import CacaoSoundCuesCore
import SwiftUI
import UniformTypeIdentifiers

// Pro 版の台本連動。ScenarioWriterSolo の台本（.scwd）をキューシートに取り込み、
// キー・リストの曲を台本の行（きっかけ）に結びつける。
//
// キューシート（.ccsc）の中に置くもの（無料版は触らないので、無料版で開いて保存しても消えない）:
//   pro.json        … 台本のファイル名・元の場所・結びつき（キュー/曲の ID → 台本の行の uid）・表示の設定
//   Script/<名前>.scwd … 取り込んだ台本のコピー

extension UTType {
    static let scenarioWriterScript = UTType(filenameExtension: "scwd") ?? .json
}

/// 台本（.scwd）のうち、表示に使うところだけを読む（知らないキー・無いキーには寛容に）
struct ScriptDocument: Decodable, Equatable {
    struct Character: Decodable, Equatable {
        var id: Int64
        var name: String
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: Keys.self)
            id = (try? c.decode(Int64.self, forKey: .id)) ?? 0
            name = (try? c.decode(String.self, forKey: .name)) ?? ""
        }
        enum Keys: String, CodingKey { case id, name }
    }

    struct Line: Decodable, Equatable {
        var type: Int
        var character: Int64?
        var text: String
        /// 行の ID（ScenarioWriterSolo で保存した台本にある）。無い古い台本は場面と行の番号で代わりの ID を作る
        var uid: String
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: Keys.self)
            type = (try? c.decode(Int.self, forKey: .type)) ?? 1
            character = try? c.decode(Int64.self, forKey: .character)
            text = (try? c.decode(String.self, forKey: .text)) ?? ""
            uid = (try? c.decode(String.self, forKey: .uid)) ?? ""
        }
        enum Keys: String, CodingKey { case type, character, text, uid }
    }

    struct Scene: Decodable, Equatable {
        var name: String
        var valid: Bool
        var lines: [Line]
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: Keys.self)
            name = (try? c.decode(String.self, forKey: .name)) ?? ""
            valid = (try? c.decode(Bool.self, forKey: .valid)) ?? true
            lines = (try? c.decode([Line].self, forKey: .lines)) ?? []
        }
        enum Keys: String, CodingKey { case name, valid, lines }
    }

    struct Style: Decodable, Equatable {
        var id: Int
        var name: String
        var indent: Int
        var abbr: String
        /// 1=名前を出す・「」で囲む 2=名前を出す 3=名前なし・「」で囲む 0=名前なし
        var mode: Int
        var color: String
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: Keys.self)
            id = (try? c.decode(Int.self, forKey: .id)) ?? 0
            name = (try? c.decode(String.self, forKey: .name)) ?? ""
            indent = (try? c.decode(Int.self, forKey: .indent)) ?? 0
            abbr = (try? c.decode(String.self, forKey: .abbr)) ?? ""
            mode = (try? c.decode(Int.self, forKey: .mode)) ?? 0
            color = (try? c.decode(String.self, forKey: .color)) ?? "#000000"
        }
        enum Keys: String, CodingKey { case id, name, indent, abbr, mode, color }
    }

    var title: String
    var characters: [Character]
    var scenes: [Scene]
    var styles: [Style]
    var kagikakko: Bool
    /// 登場人物名欄の文字数と、本文 1 行の文字数（ScenarioWriterSolo の「設定 › 書式」。紙の台本と同じ折り返しにする）
    var characterLength: Int
    var bodyLength: Int

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: Keys.self)
        guard (try? c.decode(String.self, forKey: .format)) == "scwd" else {
            throw CocoaError(.fileReadCorruptFile)
        }
        title = (try? c.nestedContainer(keyedBy: InfoKeys.self, forKey: .scenario).decode(String.self, forKey: .title)) ?? ""
        characters = (try? c.decode([Character].self, forKey: .characters)) ?? []
        scenes = (try? c.decode([Scene].self, forKey: .scenes)) ?? []
        styles = (try? c.decode([Style].self, forKey: .styles)) ?? []
        let setting = try? c.nestedContainer(keyedBy: SettingKeys.self, forKey: .setting)
        kagikakko = (try? setting?.decode(Bool.self, forKey: .kagikakko)) ?? true
        characterLength = max(2, (try? setting?.decode(Int.self, forKey: .characterLength)) ?? 8)
        bodyLength = max(4, (try? setting?.decode(Int.self, forKey: .bodyLength)) ?? 32)
        // ID の無い行（古い台本）には、場面と行の番号で代わりの ID を付ける
        for s in scenes.indices {
            for l in scenes[s].lines.indices where scenes[s].lines[l].uid.isEmpty {
                scenes[s].lines[l].uid = "pos-\(s)-\(l)"
            }
        }
    }

    enum Keys: String, CodingKey { case format, scenario, characters, scenes, styles, setting }
    enum InfoKeys: String, CodingKey { case title }
    enum SettingKeys: String, CodingKey { case kagikakko, characterLength, bodyLength }

    static func load(_ url: URL) throws -> ScriptDocument {
        try JSONDecoder().decode(ScriptDocument.self, from: Data(contentsOf: url))
    }

    func style(_ type: Int) -> Style? { styles.first { $0.id == type } }
    func characterName(_ id: Int64?) -> String? { id.flatMap { i in characters.first { $0.id == i }?.name } }

    /// 行を探す（場面の番号・行）
    func line(_ uid: String) -> (scene: Int, line: Line)? {
        for (i, s) in scenes.enumerated() {
            if let l = s.lines.first(where: { $0.uid == uid }) { return (i, l) }
        }
        return nil
    }

    /// きっかけの位置の短い説明（インスペクタ・メニュー用）。例: 太郎「…じいちゃんを▼知ってる…」
    func summary(_ anchor: CueAnchor, around: Int = 10) -> String? {
        guard let (_, l) = line(anchor.line) else { return nil }
        let chars = Array(l.text.replacingOccurrences(of: "\n", with: " "))
        let at = min(max(anchor.offset, 0), chars.count)
        let from = max(0, at - around), to = min(chars.count, at + around)
        let text = (from > 0 ? "…" : "") + String(chars[from..<at]) + "▼" + String(chars[at..<to]) + (to < chars.count ? "…" : "")
        if let name = characterName(l.character), !name.isEmpty { return "\(name)「\(text)」" }
        return text
    }
}

/// きっかけの位置: 台本の行と、その行の本文の何文字目か（0 なら行の頭）
struct CueAnchor: Codable, Equatable, Hashable {
    var line: String
    var offset: Int = 0
    /// 線の位置を文字からずらす量（文字の大きさに対する割合。台本の進む向きが＋）。
    /// 帯の上の印をドラッグして、行間などに合わせる
    var nudge: Double?

    init(line: String, offset: Int = 0) {
        self.line = line
        self.offset = offset
    }

    /// 文字列だけのもの（行の頭）も読む
    init(from d: Decoder) throws {
        if let s = try? d.singleValueContainer().decode(String.self) {
            line = s
            offset = 0
            return
        }
        let c = try d.container(keyedBy: CodingKeys.self)
        line = try c.decode(String.self, forKey: .line)
        offset = (try? c.decode(Int.self, forKey: .offset)) ?? 0
        nudge = try? c.decode(Double.self, forKey: .nudge)
    }
}

/// 帯に書く、きっかけに属さないメモ（紙の台本の余白に鉛筆で書くもの）
struct ScriptNote: Codable, Equatable, Identifiable {
    var id = UUID()
    var anchor: CueAnchor
    var text: String
}

/// pro.json の中身
struct ProData: Codable, Equatable {
    var version = 1
    /// キューシートの Script/ に置いた台本のファイル名
    var script: String?
    /// 取り込んだときの元の台本の場所（「台本を読み込み直す」用）
    var scriptSource: String?
    /// キー（KeyCue.id）・リストの曲（SequenceStep.id）→ きっかけの位置（台本の行と文字の位置）
    var links: [String: CueAnchor] = [:]
    /// 止める位置（終わり）。BGM などは、ここまで線を伸ばし「F.O.」と書く
    var ends: [String: CueAnchor] = [:]
    /// きっかけのメモ（帯のラベルの下に出す。例「Piano」）
    var memos: [String: String] = [:]
    /// 帯に書いたメモ（きっかけに属さないもの）
    var notes: [ScriptNote] = []
    /// キー・曲（id）→ 出力の系統の名前。無ければメイン
    var outputs: [String: String] = [:]
    /// 縦書きで表示する
    var vertical = true
    var fontSize: Double = 16
    /// 行間（文字の大きさに対する割合。0.2 で文字の 2 割）
    var lineSpacing: Double = 0.2
    /// 文字間（文字の大きさに対する割合。0 で詰めない・空けない）
    var charSpacing: Double = 0
    /// 人物名欄・本文 1 行の字数（nil なら台本〈ScenarioWriterSolo の書式〉のとおり）
    var nameChars: Int?
    var bodyChars: Int?
    /// Standby が移ったら、そのきっかけのページへ自動で送る（ふだんは OFF。自分でページを送る）
    var autoFollow = false

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        script = try? c.decode(String.self, forKey: .script)
        scriptSource = try? c.decode(String.self, forKey: .scriptSource)
        links = (try? c.decode([String: CueAnchor].self, forKey: .links)) ?? [:]
        ends = (try? c.decode([String: CueAnchor].self, forKey: .ends)) ?? [:]
        memos = (try? c.decode([String: String].self, forKey: .memos)) ?? [:]
        notes = (try? c.decode([ScriptNote].self, forKey: .notes)) ?? []
        outputs = (try? c.decode([String: String].self, forKey: .outputs)) ?? [:]
        vertical = (try? c.decode(Bool.self, forKey: .vertical)) ?? true
        fontSize = (try? c.decode(Double.self, forKey: .fontSize)) ?? 16
        lineSpacing = (try? c.decode(Double.self, forKey: .lineSpacing)) ?? 0.2
        charSpacing = (try? c.decode(Double.self, forKey: .charSpacing)) ?? 0
        nameChars = try? c.decode(Int.self, forKey: .nameChars)
        bodyChars = try? c.decode(Int.self, forKey: .bodyChars)
        autoFollow = (try? c.decode(Bool.self, forKey: .autoFollow)) ?? false
    }
}

@MainActor @Observable
final class ProModel {
    static let shared = ProModel()
    static let dataFile = "pro.json"
    static let scriptFolder = "Script"

    private(set) var data = ProData()
    private(set) var script: ScriptDocument?
    /// 台本のパネルを出すか（この Mac に保存）
    var showPanel = UserDefaults.standard.object(forKey: "pro.showScript") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showPanel, forKey: "pro.showScript") }
    }
    /// いま表示しているページ（0 から）と、ページの数（台本のパネルが決める）
    var page = 0
    var pageCount = 0
    /// クリックで選んだ台本の位置（結びつける相手）
    var selected: CueAnchor?
    /// 自動でページを送ってほしい行（台本のパネルがページを探して送る）
    var revealRequest: String?

    /// まだキューシートに保存していない台本（取り込んだ元のファイル）
    @ObservationIgnored private var pendingScript: URL?
    @ObservationIgnored private var packageURL: URL?

    private init() {}

    private var model: AppModel { AppModel.shared }

    // MARK: - 読み書き

    func reset() {
        data = ProData()
        script = nil
        pendingScript = nil
        packageURL = nil
        page = 0
        selected = nil
    }

    /// キューシートを開いたとき
    func load(from url: URL) {
        reset()
        packageURL = url
        if let d = try? Data(contentsOf: url.appendingPathComponent(Self.dataFile)),
           let pro = try? JSONDecoder().decode(ProData.self, from: d) {
            data = pro
        }
        if let name = data.script {
            let file = url.appendingPathComponent(Self.scriptFolder).appendingPathComponent(name)
            script = try? ScriptDocument.load(file)
        }
    }

    /// キューシートを保存したとき（別名で保存なら、前の場所の台本もコピーする）
    func save(to url: URL, from oldURL: URL?) throws {
        let fm = FileManager.default
        let folder = url.appendingPathComponent(Self.scriptFolder, isDirectory: true)
        if let name = data.script {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let dest = folder.appendingPathComponent(name)
            let source = pendingScript ?? oldURL?.appendingPathComponent(Self.scriptFolder).appendingPathComponent(name)
            if let source, source.standardizedFileURL != dest.standardizedFileURL, fm.fileExists(atPath: source.path) {
                try? fm.removeItem(at: dest)
                try fm.copyItem(at: source, to: dest)
            }
            // 使っていない古い台本は消す
            for other in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] where other != name {
                try? fm.removeItem(at: folder.appendingPathComponent(other))
            }
        } else if fm.fileExists(atPath: folder.path) {
            try? fm.removeItem(at: folder)
        }
        // 使われなくなったキー・曲の結びつきは捨てる
        var pro = data
        let ids = Set(model.show.keyCues.map(\.id.uuidString) + model.show.sequences.flatMap { $0.steps.map(\.id.uuidString) })
        pro.links = pro.links.filter { ids.contains($0.key) }
        pro.ends = pro.ends.filter { ids.contains($0.key) && pro.links[$0.key] != nil }
        pro.memos = pro.memos.filter { ids.contains($0.key) && !$0.value.isEmpty }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(pro).write(to: url.appendingPathComponent(Self.dataFile), options: .atomic)
        data = pro
        pendingScript = nil
        packageURL = url
    }

    /// 台本（.scwd）を選んで取り込む
    func importScript() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.scenarioWriterScript, .json]
        panel.message = L("ScenarioWriterSolo の台本（.scwd）を選んでください")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importScript(from: url)
    }

    func importScript(from url: URL) {
        do {
            let doc = try ScriptDocument.load(url)
            script = doc
            pendingScript = url
            data.script = url.lastPathComponent
            data.scriptSource = url.path
            page = 0
            selected = nil
            showPanel = true
            model.markDirty()
            let missing = data.links.values.filter { doc.line($0.line) == nil }.count
            if missing > 0 {
                model.message = L("台本の中に見つからない行が %d か所あります。インスペクタの「きっかけ」を確かめてください。", missing)
            }
        } catch {
            model.message = L("台本を読み込めません: %@", url.lastPathComponent)
        }
    }

    /// 取り込んだときの元の台本から、もう一度読み込む（台本を直したとき）
    func reloadScript() {
        guard let path = data.scriptSource, FileManager.default.fileExists(atPath: path) else {
            importScript()
            return
        }
        importScript(from: URL(fileURLWithPath: path))
    }

    func removeScript() {
        script = nil
        pendingScript = nil
        data.script = nil
        data.scriptSource = nil
        model.markDirty()
    }

    func setVertical(_ v: Bool) { data.vertical = v; page = 0; model.markDirty() }
    func setFontSize(_ s: Double) { data.fontSize = s; model.markDirty() }
    func setLineSpacing(_ s: Double) { data.lineSpacing = s; model.markDirty() }
    func setCharSpacing(_ s: Double) { data.charSpacing = s; model.markDirty() }
    /// キー・曲の出力の系統（名前。nil ならメイン）
    func setOutput(_ cueID: UUID, _ name: String?) {
        data.outputs[cueID.uuidString] = name
        model.markDirty()
    }

    /// 出力の系統の名前を変えたとき、このキューシートの指定も付け替える
    func renameOutput(_ old: String, to new: String) {
        var changed = false
        for (k, v) in data.outputs where v == old {
            data.outputs[k] = new
            changed = true
        }
        if changed { model.markDirty() }
    }

    func setNameChars(_ n: Int?) { data.nameChars = n; model.markDirty() }
    func setBodyChars(_ n: Int?) { data.bodyChars = n; model.markDirty() }

    /// 表示に使う台本（1 行の字数をキューシートの設定で上書きしたもの）
    var displayScript: ScriptDocument? {
        guard var s = script else { return nil }
        if let n = data.nameChars { s.characterLength = n }
        if let n = data.bodyChars { s.bodyLength = n }
        return s
    }
    func setAutoFollow(_ v: Bool) { data.autoFollow = v; model.markDirty() }

    // MARK: - 結びつき

    func anchor(for cueID: UUID) -> CueAnchor? { data.links[cueID.uuidString] }

    func link(_ cueID: UUID, to anchor: CueAnchor) {
        data.links[cueID.uuidString] = anchor
        model.markDirty()
    }

    func unlink(_ cueID: UUID) {
        data.links[cueID.uuidString] = nil
        data.ends[cueID.uuidString] = nil
        model.markDirty()
    }

    func end(for cueID: UUID) -> CueAnchor? { data.ends[cueID.uuidString] }

    /// 止める位置を決める（始まりより前なら入れ替える）
    func setEnd(_ cueID: UUID, at anchor: CueAnchor?) {
        data.ends[cueID.uuidString] = anchor
        model.markDirty()
    }

    /// 線の始まり（isEnd なら終わり）の位置を、文字からずらす（nil で文字の位置に戻す）
    func setNudge(_ cueID: UUID, isEnd: Bool, _ value: Double?) {
        let key = cueID.uuidString
        let v = value.map { ($0 * 100).rounded() / 100 }
        if isEnd {
            guard data.ends[key] != nil else { return }
            data.ends[key]?.nudge = v == 0 ? nil : v
        } else {
            guard data.links[key] != nil else { return }
            data.links[key]?.nudge = v == 0 ? nil : v
        }
        model.markDirty()
    }

    func memo(for cueID: UUID) -> String { data.memos[cueID.uuidString] ?? "" }

    func setMemo(_ cueID: UUID, _ text: String) {
        data.memos[cueID.uuidString] = text.isEmpty ? nil : text
        model.markDirty()
    }

    /// 帯にメモを書く（空なら書かない）
    func addNote(at anchor: CueAnchor, _ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        data.notes.append(ScriptNote(anchor: anchor, text: t))
        model.markDirty()
    }

    /// 帯のメモを直す（空にしたら消す）
    func setNote(_ id: UUID, _ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { data.notes.removeAll { $0.id == id } } else if let i = data.notes.firstIndex(where: { $0.id == id }) { data.notes[i].text = t }
        model.markDirty()
    }

    /// 文字を 1 行入れてもらう（メモ用）。取り消したら nil
    func askText(title: String, initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(string: initial)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: L("キャンセル"))
        alert.window.initialFirstResponder = field
        let ok = alert.runModal() == .alertFirstButtonReturn
        AppModel.endEditing()
        return ok ? field.stringValue : nil
    }

    /// 結びついたキュー全部（帯に描く）
    func allMarks() -> [CueMark] {
        var out: [CueMark] = []
        for cue in model.show.keyCues {
            if let a = anchor(for: cue.id) {
                out.append(CueMark(id: cue.id, kind: .key(cue.keyCode, cue.colorIndex), name: cue.name, offset: a.offset,
                                   start: a, end: end(for: cue.id), memo: memo(for: cue.id), fades: cue.play.fadeOut > 0))
            }
        }
        for seq in model.show.sequences {
            for (i, step) in seq.steps.enumerated() {
                if let a = anchor(for: step.id) {
                    out.append(CueMark(id: step.id, kind: .step(i + 1), name: step.name, offset: a.offset,
                                       start: a, end: end(for: step.id), memo: memo(for: step.id), fades: step.play.fadeOut > 0))
                }
            }
        }
        return out
    }

    /// 台本の行に結びついたキュー（キー・リストの曲）。offset はその行の中の位置
    func marks(for uid: String) -> [CueMark] {
        allMarks().filter { $0.start.line == uid }.sorted { $0.offset < $1.offset }
    }

    /// いま選んでいるキュー（キーかリストの曲）。台本の行を右クリックして結びつける相手
    /// その印の音が鳴っているか
    func isPlaying(markID: UUID) -> Bool {
        model.status.contains { $0.tag == markID && !$0.armed }
    }

    /// その印の音だけを止める（Esc の全停止ではなく、その音のフェードアウト設定で）。
    /// リストの曲は、曲だけ止めると次の曲が続いて鳴ることがあるので、そのリストを停止フェードで止める
    func stop(markID: UUID) {
        for seq in model.show.sequences where seq.steps.contains(where: { $0.id == markID }) {
            if model.isRunning(seq.id) { model.stopSequence(seq.id) }
            return
        }
        for st in model.status where st.tag == markID {
            model.output.mixer.send(.stopToken(st.token, fadeFrames: -1))
        }
    }

    /// 台本の印から鳴らす（⌘／control＋クリック）。キーはそのキーを押したのと同じ、リストの曲はその曲から始める
    func play(markID: UUID) {
        if let cue = model.show.keyCues.first(where: { $0.id == markID }) {
            model.trigger(cue)
            return
        }
        for seq in model.show.sequences {
            if let i = seq.steps.firstIndex(where: { $0.id == markID }) {
                model.startSequence(seq.id, from: i)
                return
            }
        }
    }

    var selectedCue: CueMark? {
        switch model.selection {
        case .key(let code):
            guard let cue = model.show.keyCues.first(where: { $0.keyCode == code }) else { return nil }
            return CueMark(id: cue.id, kind: .key(cue.keyCode, cue.colorIndex), name: cue.name, offset: 0,
                           start: CueAnchor(line: ""), end: nil, memo: "", fades: cue.play.fadeOut > 0)
        case let .step(seqID, stepID):
            guard let seq = model.show.sequences.first(where: { $0.id == seqID }),
                  let i = seq.steps.firstIndex(where: { $0.id == stepID }) else { return nil }
            return CueMark(id: stepID, kind: .step(i + 1), name: seq.steps[i].name, offset: 0,
                           start: CueAnchor(line: ""), end: nil, memo: "", fades: seq.steps[i].play.fadeOut > 0)
        case .none:
            return nil
        }
    }

    /// 次に鳴る（Standby）・鳴っているキューの ID（台本の印を明るくする）
    var activeCueIDs: Set<UUID> {
        var ids = Set<UUID>()
        if let seqID = model.activeSequenceID, let seq = model.show.sequences.first(where: { $0.id == seqID }),
           let i = model.upcomingIndex(seqID), seq.steps.indices.contains(i) {
            ids.insert(seq.steps[i].id)
        }
        for v in model.status where !v.armed {
            ids.insert(v.owner)
            ids.insert(v.tag)
        }
        return ids
    }

    // MARK: - キー

    /// ← →: 台本のページを送る。縦書きは本と同じく ← が次のページ
    func handleKey(_ code: UInt16) -> Bool {
        guard script != nil, showPanel, code == 123 || code == 124 else { return false }
        let forward = (code == 123) == data.vertical
        turn(forward ? 1 : -1)
        return true
    }

    func turn(_ delta: Int) {
        page = min(max(page + delta, 0), max(0, pageCount - 1))
    }
}

/// 台本の行に付ける印（キーの文字か、リストの曲の番号）
struct CueMark: Equatable, Identifiable {
    enum Kind: Equatable {
        case key(UInt16, Int)
        case step(Int)
    }
    var id: UUID
    var kind: Kind
    var name: String
    /// 行の本文の中の位置（何文字目の前か）
    var offset: Int
    /// 始まり・止める位置（帯に線を描く）・メモ
    var start: CueAnchor
    var end: CueAnchor?
    var memo: String
    /// フェードアウトして止めるか（終わりの印を F.O. にするか C.O. にするか）
    var fades: Bool

    var endLabel: String { fades ? "F.O." : "C.O." }

    /// 印の文字（キーなら A、リストの曲なら ≡3。≡ はキーボードの「リストの開始／停止キー」と同じ印）
    var label: String {
        switch kind {
        case .key(let code, _): return KeyboardLayout.label(code)
        case .step(let n): return "≡\(n)"
        }
    }

    var color: NSColor {
        switch kind {
        case .key(_, let i): return NSColor(AppModel.colors[i % AppModel.colors.count])
        case .step: return .systemIndigo
        }
    }
}

import AppKit
import CacaoSoundCuesCore
import CoreMIDI
import SwiftUI

// MIDI コントロール（Pro 版）。
// 受ける: MIDI コントローラ・パッド・フットペダルのノート／CC／プログラムチェンジ、照明卓などからの MSC（MIDI Show Control）で、
//   キー・Return・スペース・Esc・Standby・台本のページ・全体の音量を操作する。どの合図で何をするかは「覚えさせる」（押して覚える）。
// 送る: キー・リストの曲が鳴り始めたときに、照明卓などへノート／CC／プログラムチェンジ／MSC の GO を送る。
// 割り当て（合図 → 操作、キー・曲 → 送るもの）はキューシート（pro.json）に保存。どの機器を使うかは Mac ごとに違うので、この Mac に保存する。
// 受けた操作は AppModel の操作の入口を通るので、バックアップ機との同時運転にもそのまま乗る（バックアップ機では手の操作と同じく効かない）

/// 受ける合図
enum MIDITrigger: Codable, Hashable {
    /// チャンネルは 0〜15（画面では 1〜16）
    case note(channel: Int, note: Int)
    case cc(channel: Int, number: Int)
    case program(channel: Int, number: Int)
    /// MSC の命令（GO = 1 …）。cue が nil なら、キューの番号を問わない（番号つきの割り当てが無いときに使う）
    case msc(command: Int, cue: String?)

    var label: String {
        switch self {
        case let .note(ch, n): return L("ノート %@（%d）ch%d", MIDINames.note(n), n, ch + 1)
        case let .cc(ch, n): return L("CC %d ch%d", n, ch + 1)
        case let .program(ch, n): return L("プログラム %d ch%d", n + 1, ch + 1)
        case let .msc(cmd, cue):
            let name = MIDINames.mscCommand(cmd)
            if let cue, !cue.isEmpty { return L("MSC %@ キュー %@", name, cue) }
            return L("MSC %@（キューの番号を問わない）", name)
        }
    }
}

/// 合図を受けたときの操作
enum MIDIAction: Codable, Hashable {
    /// そのキーを押したのと同じ（KeyCue.id）
    case cue(UUID)
    /// リストの開始／停止（CueSequence.id）
    case sequence(UUID)
    case advance
    case endSong
    case panic
    case standbyUp
    case standbyDown
    case pageNext
    case pagePrev
    /// CC の値（0〜127）で全体の音量
    case masterVolume
    case none
}

/// 合図と操作の組
struct MIDIBinding: Codable, Equatable, Identifiable {
    var id = UUID()
    var trigger: MIDITrigger?
    var action: MIDIAction = .none
}

/// キー・曲が鳴り始めたときに送るもの
enum MIDISend: Codable, Hashable {
    /// ノートオンを送り、少しあとにノートオフ
    case note(channel: Int, note: Int, velocity: Int)
    case cc(channel: Int, number: Int, value: Int)
    case program(channel: Int, number: Int)
    /// MSC の GO（キューの番号）
    case mscGo(cue: String)

    enum Kind: String, CaseIterable { case note, cc, program, mscGo }

    var kind: Kind {
        switch self {
        case .note: return .note
        case .cc: return .cc
        case .program: return .program
        case .mscGo: return .mscGo
        }
    }

    static func make(_ kind: Kind) -> MIDISend {
        switch kind {
        case .note: return .note(channel: 0, note: 60, velocity: 127)
        case .cc: return .cc(channel: 0, number: 1, value: 127)
        case .program: return .program(channel: 0, number: 0)
        case .mscGo: return .mscGo(cue: "1")
        }
    }

    var label: String {
        switch self {
        case let .note(ch, n, v): return L("ノート %@（%d）ch%d 強さ %d", MIDINames.note(n), n, ch + 1, v)
        case let .cc(ch, n, v): return L("CC %d = %d ch%d", n, v, ch + 1)
        case let .program(ch, n): return L("プログラム %d ch%d", n + 1, ch + 1)
        case let .mscGo(cue): return L("MSC GO キュー %@", cue)
        }
    }
}

/// pro.json の MIDI のところ
struct MIDISettings: Codable, Equatable {
    /// 合図 → 操作
    var bindings: [MIDIBinding] = []
    /// キー・曲（id）→ 鳴り始めたときに送るもの
    var sends: [String: MIDISend] = [:]
    /// MSC で受ける機器の番号（0〜111。127 なら番号を問わない）
    var mscReceiveID = 127
    /// MSC を送るときの機器の番号（127 は「すべて」）
    var mscSendID = 127

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        bindings = (try? c.decode([MIDIBinding].self, forKey: .bindings)) ?? []
        sends = (try? c.decode([String: MIDISend].self, forKey: .sends)) ?? [:]
        mscReceiveID = (try? c.decode(Int.self, forKey: .mscReceiveID)) ?? 127
        mscSendID = (try? c.decode(Int.self, forKey: .mscSendID)) ?? 127
    }
}

enum MIDINames {
    private static let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// ノートの名前（60 = C3。Logic・多くの機材と同じ数え方）
    static func note(_ n: Int) -> String { "\(names[((n % 12) + 12) % 12])\(n / 12 - 2)" }

    static func mscCommand(_ c: Int) -> String {
        switch c {
        case 0x01: return "GO"
        case 0x02: return "STOP"
        case 0x03: return "RESUME"
        case 0x04: return "TIMED GO"
        case 0x05: return "LOAD"
        case 0x06: return "SET"
        case 0x07: return "FIRE"
        case 0x08: return "ALL OFF"
        case 0x09: return "RESTORE"
        case 0x0A: return "RESET"
        case 0x0B: return "GO OFF"
        default: return String(format: "0x%02X", c)
        }
    }
}

/// MIDI の機器（入力のもとか、出力の行き先）
struct MIDIEndpointInfo: Identifiable, Hashable {
    var id: String { name }
    var ref: MIDIEndpointRef
    var name: String

    static func sources() -> [MIDIEndpointInfo] {
        (0..<MIDIGetNumberOfSources()).compactMap { info(MIDIGetSource($0)) }
    }

    static func destinations() -> [MIDIEndpointInfo] {
        (0..<MIDIGetNumberOfDestinations()).compactMap { info(MIDIGetDestination($0)) }
    }

    private static func info(_ ref: MIDIEndpointRef) -> MIDIEndpointInfo? {
        guard ref != 0 else { return nil }
        var name: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(ref, kMIDIPropertyDisplayName, &name) == noErr, let name else { return nil }
        return MIDIEndpointInfo(ref: ref, name: name.takeRetainedValue() as String)
    }
}

@MainActor @Observable
final class ProMIDI {
    static let shared = ProMIDI()

    /// 受ける機器の名前（nil ならすべての MIDI 入力）。この Mac に保存
    var inputName: String? = UserDefaults.standard.string(forKey: "pro.midi.input") {
        didSet {
            UserDefaults.standard.set(inputName, forKey: "pro.midi.input")
            connectSources()
        }
    }
    /// 送る機器の名前（nil なら送らない）。この Mac に保存
    var outputName: String? = UserDefaults.standard.string(forKey: "pro.midi.output") {
        didSet { UserDefaults.standard.set(outputName, forKey: "pro.midi.output") }
    }
    private(set) var sources: [MIDIEndpointInfo] = []
    private(set) var destinations: [MIDIEndpointInfo] = []
    /// 最後に受けた合図（画面に出す。割り当てを作るときの目安）
    private(set) var lastReceived = ""
    /// 「覚えさせる」を押した割り当て。次に受けた合図をこれに入れる
    var learning: UUID?
    /// 始められなかったとき
    private(set) var problem: String?

    private var client = MIDIClientRef()
    private var inPort = MIDIPortRef()
    private var outPort = MIDIPortRef()
    private var connected: [MIDIEndpointRef] = []
    /// CC を「押した」とみなすため、前の値を覚える（チャンネル × 番号）
    private var lastCC: [Int: Int] = [:]

    private var pro: ProModel { ProModel.shared }
    private var model: AppModel { AppModel.shared }
    var settings: MIDISettings { pro.data.midi }

    private init() {}

    /// 起動したとき
    func startUp() {
        var status = MIDIClientCreateWithBlock("CacaoSoundCuesPro" as CFString, &client) { note in
            // 機器の抜き差し
            guard note.pointee.messageID == .msgSetupChanged else { return }
            DispatchQueue.main.async { ProMIDI.shared.refresh() }
        }
        if status == noErr {
            status = MIDIInputPortCreateWithProtocol(client, "Input" as CFString, ._1_0, &inPort) { list, _ in
                // MIDI のスレッドから呼ばれる。中身を写してからメインへ
                var words: [UInt32] = []
                for p in list.unsafeSequence() {
                    let n = Int(p.pointee.wordCount)
                    withUnsafeBytes(of: p.pointee.words) { raw in
                        words.append(contentsOf: raw.bindMemory(to: UInt32.self).prefix(n))
                    }
                }
                DispatchQueue.main.async { ProMIDI.shared.receive(words) }
            }
        }
        if status == noErr {
            status = MIDIOutputPortCreate(client, "Output" as CFString, &outPort)
        }
        problem = status == noErr ? nil : L("MIDI を始められません（%d）", Int(status))
        refresh()
    }

    func refresh() {
        sources = MIDIEndpointInfo.sources()
        destinations = MIDIEndpointInfo.destinations()
        connectSources()
    }

    private func connectSources() {
        guard inPort != 0 else { return }
        for s in connected { MIDIPortDisconnectSource(inPort, s) }
        connected = sources.filter { inputName == nil || $0.name == inputName }.map(\.ref)
        for s in connected { MIDIPortConnectSource(inPort, s, nil) }
    }

    // MARK: - 受ける

    /// UMP（MIDI 1.0 のチャンネルボイスと、7 バイトずつのシステムエクスクルーシブ）を読む
    private var sysex: [UInt8] = []

    private func receive(_ words: [UInt32]) {
        var i = 0
        while i < words.count {
            let w = words[i]
            let type = Int(w >> 28)
            let size: Int
            switch type {
            case 0, 1, 2, 6, 7: size = 1
            case 3, 4, 8, 9, 10: size = 2
            case 11, 12: size = 3
            default: size = 4
            }
            if type == 2 {
                channelVoice(UInt8((w >> 16) & 0xFF), Int((w >> 8) & 0x7F), Int(w & 0x7F))
            } else if type == 3, i + 1 < words.count {
                let state = Int((w >> 20) & 0xF)
                let count = min(6, Int((w >> 16) & 0xF))
                let w2 = words[i + 1]
                let bytes: [UInt8] = [UInt8((w >> 8) & 0xFF), UInt8(w & 0xFF),
                                      UInt8(w2 >> 24), UInt8((w2 >> 16) & 0xFF), UInt8((w2 >> 8) & 0xFF), UInt8(w2 & 0xFF)]
                // 0: 1 つで完結、1: 始まり、2: 続き、3: 終わり
                if state == 0 || state == 1 { sysex = [] }
                sysex.append(contentsOf: bytes.prefix(count))
                if state == 0 || state == 3 { systemExclusive(sysex) }
            }
            i += size
        }
    }

    private func channelVoice(_ status: UInt8, _ d1: Int, _ d2: Int) {
        let ch = Int(status & 0x0F)
        switch status & 0xF0 {
        case 0x90 where d2 > 0:
            received(.note(channel: ch, note: d1), value: d2)
        case 0xB0:
            let key = ch * 128 + d1
            let before = lastCC[key] ?? 0
            lastCC[key] = d2
            received(.cc(channel: ch, number: d1), value: d2, pressed: before < 64 && d2 >= 64)
        case 0xC0:
            received(.program(channel: ch, number: d1), value: 127)
        default:
            break
        }
    }

    /// MSC: F0 7F <機器の番号> 02 <命令の形式> <命令> <データ> F7（UMP では F0・F7 は付かない）
    private func systemExclusive(_ bytes: [UInt8]) {
        guard bytes.count >= 5, bytes[0] == 0x7F, bytes[2] == 0x02 else { return }
        let device = Int(bytes[1])
        let mine = settings.mscReceiveID
        guard mine == 127 || device == 127 || device == mine else { return }
        let command = Int(bytes[4])
        // データの最初の区切り（00）までがキューの番号（数字と「.」）
        let data = bytes.dropFirst(5).prefix { $0 != 0x00 && $0 != 0xF7 }
        let cue = String(decoding: data, as: UTF8.self)
        received(.msc(command: command, cue: cue.isEmpty ? nil : cue), value: 127)
    }

    /// 合図を受けたとき。pressed はボタンを押したとき（CC は 64 をまたいで上がったとき）
    private func received(_ trigger: MIDITrigger, value: Int, pressed: Bool = true) {
        lastReceived = trigger.label
        if let id = learning {
            // 覚えさせているとき: CC は値を問わず、MSC はキューの番号ごと覚える
            learning = nil
            setTrigger(id, trigger)
            return
        }
        guard let binding = binding(for: trigger) else { return }
        if binding.action == .masterVolume {
            // 全体の音量は CC のつまみ・フェーダーで（0〜127 → -40〜+6 dB）
            guard case .cc = trigger else { return }
            model.show.masterVolumeDB = (Double(value) / 127 * 46 - 40).rounded()
            model.applyMasterVolume()
            return
        }
        guard pressed else { return }
        perform(binding.action)
    }

    /// 合図に合う割り当て。MSC はキューの番号まで合うものが先、無ければ番号を問わないもの
    private func binding(for trigger: MIDITrigger) -> MIDIBinding? {
        let list = settings.bindings
        if let b = list.first(where: { $0.trigger == trigger && $0.action != .none }) { return b }
        if case let .msc(cmd, cue?) = trigger, !cue.isEmpty {
            return list.first { $0.trigger == .msc(command: cmd, cue: nil) && $0.action != .none }
        }
        return nil
    }

    /// 操作（どれも、キー・画面で操作したときと同じ入口を通る）
    private func perform(_ action: MIDIAction) {
        let m = model
        switch action {
        case .cue(let id):
            if let cue = m.show.keyCues.first(where: { $0.id == id }) { m.trigger(cue) }
        case .sequence(let id):
            if m.show.sequences.contains(where: { $0.id == id }) { m.toggleSequence(id) }
        case .advance: m.advanceActiveSequence()
        case .endSong: m.endCurrentSequenceSong()
        case .panic: m.panic()
        case .standbyUp: m.moveCue(by: -1)
        case .standbyDown: m.moveCue(by: 1)
        case .pageNext: if pro.hasScript { pro.turn(1) }
        case .pagePrev: if pro.hasScript { pro.turn(-1) }
        case .masterVolume, .none: break
        }
    }

    // MARK: - 割り当て（キューシートに保存）

    func addBinding(_ b: MIDIBinding = MIDIBinding()) {
        pro.updateMIDI { $0.bindings.append(b) }
    }

    func removeBinding(_ id: UUID) {
        if learning == id { learning = nil }
        pro.updateMIDI { $0.bindings.removeAll { $0.id == id } }
    }

    func setTrigger(_ id: UUID, _ t: MIDITrigger?) {
        pro.updateMIDI { s in
            guard let i = s.bindings.firstIndex(where: { $0.id == id }) else { return }
            s.bindings[i].trigger = t
        }
    }

    func setAction(_ id: UUID, _ a: MIDIAction) {
        pro.updateMIDI { s in
            guard let i = s.bindings.firstIndex(where: { $0.id == id }) else { return }
            s.bindings[i].action = a
        }
    }

    /// MSC のよく使う割り当て（GO → Return、STOP → スペース、ALL OFF → Esc）。もうあるものは足さない
    func addMSCDefaults() {
        let defaults: [(Int, MIDIAction)] = [(0x01, .advance), (0x02, .endSong), (0x08, .panic)]
        pro.updateMIDI { s in
            for (cmd, action) in defaults where !s.bindings.contains(where: { $0.trigger == .msc(command: cmd, cue: nil) }) {
                s.bindings.append(MIDIBinding(trigger: .msc(command: cmd, cue: nil), action: action))
            }
        }
    }

    func setMSCReceiveID(_ n: Int) { pro.updateMIDI { $0.mscReceiveID = min(max(n, 0), 127) } }
    func setMSCSendID(_ n: Int) { pro.updateMIDI { $0.mscSendID = min(max(n, 0), 127) } }

    /// そのキーを鳴らす合図（インスペクタに出す）
    func binding(forCue id: UUID) -> MIDIBinding? {
        settings.bindings.first { $0.action == .cue(id) }
    }

    /// インスペクタの「覚えさせる」: そのキーの割り当てを作って（あれば使って）覚えさせる
    func learn(forCue id: UUID) {
        if let b = binding(forCue: id) {
            learning = b.id
        } else {
            let b = MIDIBinding(action: .cue(id))
            addBinding(b)
            learning = b.id
        }
    }

    // MARK: - 送る

    func send(for id: UUID) -> MIDISend? { settings.sends[id.uuidString] }

    func setSend(_ s: MIDISend?, for id: UUID) {
        pro.updateMIDI { $0.sends[id.uuidString] = s }
    }

    /// キー・曲が鳴り始めたとき（AppModel から）。delay は Return を押してから待つ秒数。
    /// バックアップ機は送らない（照明卓などに 2 回届かないように。引き継いだら送る）
    func played(_ id: UUID, delay: Double = 0) {
        guard let s = send(for: id), ProSync.shared.role != .backup else { return }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { ProMIDI.shared.transmit(s) }
        } else {
            transmit(s)
        }
    }

    /// 送る（設定の「試しに送る」からも）
    func transmit(_ s: MIDISend) {
        guard outPort != 0, let name = outputName, let dest = destinations.first(where: { $0.name == name }) else { return }
        switch s {
        case let .note(ch, n, v):
            let on = 0x2000_0000 | UInt32(0x90 | (ch & 0x0F)) << 16 | UInt32(n & 0x7F) << 8 | UInt32(v & 0x7F)
            sendWords([on], to: dest.ref)
            let off = 0x2000_0000 | UInt32(0x80 | (ch & 0x0F)) << 16 | UInt32(n & 0x7F) << 8
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.sendWords([off], to: dest.ref) }
        case let .cc(ch, n, v):
            sendWords([0x2000_0000 | UInt32(0xB0 | (ch & 0x0F)) << 16 | UInt32(n & 0x7F) << 8 | UInt32(v & 0x7F)], to: dest.ref)
        case let .program(ch, n):
            sendWords([0x2000_0000 | UInt32(0xC0 | (ch & 0x0F)) << 16 | UInt32(n & 0x7F) << 8], to: dest.ref)
        case let .mscGo(cue):
            // 命令の形式は 7F（すべての種類の機器）
            let number = Array(cue.utf8.filter { ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2E })
            sendSysex([0x7F, UInt8(settings.mscSendID & 0x7F), 0x02, 0x7F, 0x01] + number, to: dest.ref)
        }
    }

    /// システムエクスクルーシブ（F0・F7 を除く中身）を、UMP の 6 バイトずつに分けて送る
    private func sendSysex(_ bytes: [UInt8], to dest: MIDIEndpointRef) {
        var words: [UInt32] = []
        let chunks = stride(from: 0, to: max(bytes.count, 1), by: 6).map { Array(bytes[$0..<min($0 + 6, bytes.count)]) }
        for (i, chunk) in chunks.enumerated() {
            let state: UInt32 = chunks.count == 1 ? 0 : i == 0 ? 1 : i == chunks.count - 1 ? 3 : 2
            var b = chunk + [UInt8](repeating: 0, count: 6 - chunk.count)
            b = Array(b.prefix(6))
            words.append(0x3000_0000 | state << 20 | UInt32(chunk.count) << 16 | UInt32(b[0]) << 8 | UInt32(b[1]))
            words.append(UInt32(b[2]) << 24 | UInt32(b[3]) << 16 | UInt32(b[4]) << 8 | UInt32(b[5]))
        }
        sendWords(words, to: dest)
    }

    /// UMP の語（まとまったメッセージ）を送る
    private func sendWords(_ words: [UInt32], to dest: MIDIEndpointRef) {
        guard !words.isEmpty else { return }
        var list = MIDIEventList()
        var packet = MIDIEventListInit(&list, ._1_0)
        words.withUnsafeBufferPointer { buf in
            packet = MIDIEventListAdd(&list, MemoryLayout<MIDIEventList>.size, packet, 0, buf.count, buf.baseAddress!)
        }
        MIDISendEventList(outPort, dest, &list)
    }
}

// MARK: - 画面

/// 上の帯の「MIDI」から開く、MIDI の設定
struct MIDISheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    private var midi: ProMIDI { ProMIDI.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("MIDI コントロール")).font(.title3.bold())
            Text(L("MIDI コントローラ・フットペダルや照明卓（MSC）の合図で操作します。「覚えさせる」を押してから、コントローラのボタンを押す（照明卓から送る）と、その合図を覚えます。割り当てはキューシートに、使う機器はこの Mac に保存されます。"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let p = midi.problem {
                Text(p).foregroundStyle(.red)
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text(L("受ける機器"))
                    Picker("", selection: Binding(get: { midi.inputName }, set: { midi.inputName = $0 })) {
                        Text(L("すべての MIDI 入力")).tag(String?.none)
                        ForEach(midi.sources) { s in Text(s.name).tag(Optional(s.name)) }
                        if let n = midi.inputName, !midi.sources.contains(where: { $0.name == n }) {
                            Text(L("%@（つながっていません）", n)).tag(Optional(n))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 280)
                    Text(midi.lastReceived.isEmpty ? L("まだ何も受けていません") : L("受けた合図: %@", midi.lastReceived))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text(L("送る機器"))
                    Picker("", selection: Binding(get: { midi.outputName }, set: { midi.outputName = $0 })) {
                        Text(L("送らない")).tag(String?.none)
                        ForEach(midi.destinations) { d in Text(d.name).tag(Optional(d.name)) }
                        if let n = midi.outputName, !midi.destinations.contains(where: { $0.name == n }) {
                            Text(L("%@（つながっていません）", n)).tag(Optional(n))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 280)
                    Text(L("キー・曲ごとに、インスペクタの「MIDI を送る」で決めます"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text(L("MSC の機器の番号"))
                    HStack(spacing: 6) {
                        Text(L("受ける"))
                        DeviceIDField(value: midi.settings.mscReceiveID) { midi.setMSCReceiveID($0) }
                        Text(L("送る"))
                        DeviceIDField(value: midi.settings.mscSendID) { midi.setMSCSendID($0) }
                    }
                    Text(L("127 は「すべて」（受けるときは番号を問わない）"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(model.showMode)

            Divider()
            Text(L("割り当て（このキューシート）")).font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if midi.settings.bindings.isEmpty {
                        Text(L("まだありません。「割り当てを足す」で作ります"))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(midi.settings.bindings) { b in
                        BindingRow(binding: b)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120, maxHeight: 320)
            .disabled(model.showMode)
            HStack {
                Button { midi.addBinding() } label: { Label(L("割り当てを足す"), systemImage: "plus") }
                Button { midi.addMSCDefaults() } label: { Label(L("MSC のよく使う割り当てを足す"), systemImage: "wand.and.stars") }
                    .help(L("GO → Return（次の曲）、STOP → スペース（今の曲を終える）、ALL OFF → Esc（全部止める）"))
                Spacer()
                Button(L("閉じる")) {
                    midi.learning = nil
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .disabled(model.showMode)
        }
        .padding(20)
        .frame(width: 720)
        .onAppear { midi.refresh() }
    }
}

/// MSC の機器の番号の欄
private struct DeviceIDField: View {
    let value: Int
    let set: (Int) -> Void

    var body: some View {
        TextField("", value: Binding(get: { value }, set: { set($0) }), format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 50)
    }
}

/// 割り当ての 1 行: 合図（覚えさせる）→ 操作
private struct BindingRow: View {
    @Environment(AppModel.self) private var model
    let binding: MIDIBinding
    private var midi: ProMIDI { ProMIDI.shared }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if midi.learning == binding.id {
                    Text(L("合図を待っています…")).foregroundStyle(Color.accentColor)
                } else if let t = binding.trigger {
                    Text(t.label)
                } else {
                    Text(L("（合図なし）")).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .frame(width: 230, alignment: .leading)
            Button(midi.learning == binding.id ? L("やめる") : L("覚えさせる")) {
                midi.learning = midi.learning == binding.id ? nil : binding.id
            }
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            MIDIActionPicker(action: binding.action) { midi.setAction(binding.id, $0) }
                .frame(width: 260)
            Button { midi.removeBinding(binding.id) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help(L("この割り当てを消す"))
        }
    }
}

/// 合図で何をするか
private struct MIDIActionPicker: View {
    @Environment(AppModel.self) private var model
    let action: MIDIAction
    let set: (MIDIAction) -> Void

    var body: some View {
        Picker("", selection: Binding(get: { action }, set: set)) {
            Text(L("（何もしない）")).tag(MIDIAction.none)
            Divider()
            Text(L("Return（次の曲）")).tag(MIDIAction.advance)
            Text(L("スペース（今の曲を終える）")).tag(MIDIAction.endSong)
            Text(L("Esc（全部止める）")).tag(MIDIAction.panic)
            Text(L("↑（Standby を上へ）")).tag(MIDIAction.standbyUp)
            Text(L("↓（Standby を下へ）")).tag(MIDIAction.standbyDown)
            Text(L("台本の次のページ")).tag(MIDIAction.pageNext)
            Text(L("台本の前のページ")).tag(MIDIAction.pagePrev)
            Text(L("全体の音量（CC のつまみ・フェーダー）")).tag(MIDIAction.masterVolume)
            Divider()
            ForEach(model.show.keyCues) { cue in
                Text(L("キー %@: %@", KeyboardLayout.label(cue.keyCode), cue.name)).tag(MIDIAction.cue(cue.id))
            }
            ForEach(model.show.sequences) { seq in
                Text(L("リスト「%@」の開始／停止", seq.name)).tag(MIDIAction.sequence(seq.id))
            }
            // 消したキー・リストを指している割り当て
            if !known(action) {
                Text(L("（消したキー・リスト）")).tag(action)
            }
        }
        .labelsHidden()
    }

    private func known(_ a: MIDIAction) -> Bool {
        switch a {
        case .cue(let id): return model.show.keyCues.contains { $0.id == id }
        case .sequence(let id): return model.show.sequences.contains { $0.id == id }
        default: return true
        }
    }
}

/// インスペクタの MIDI の行: このキーを鳴らす合図（キーだけ）と、鳴り始めたときに送るもの
struct ProMIDIRow: View {
    @Environment(AppModel.self) private var model
    let cueID: UUID
    private var midi: ProMIDI { ProMIDI.shared }

    private var isKey: Bool { model.show.keyCues.contains { $0.id == cueID } }

    var body: some View {
        let send = midi.send(for: cueID)
        if isKey || midi.outputName != nil || send != nil {
            VStack(alignment: .leading, spacing: 6) {
                if isKey { receiveRow }
                if midi.outputName != nil || send != nil { sendRow(send) }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.08)))
            .disabled(model.showMode)
        }
    }

    private var receiveRow: some View {
        HStack(spacing: 8) {
            Label(L("MIDI で鳴らす"), systemImage: "pianokeys")
                .fixedSize()
            let b = midi.binding(forCue: cueID)
            if let b, midi.learning == b.id {
                Text(L("合図を待っています…")).foregroundStyle(Color.accentColor)
            } else if let t = b?.trigger {
                Text(t.label).lineLimit(1)
            } else {
                Text(L("なし")).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let b, midi.learning == b.id {
                Button(L("やめる")) { midi.learning = nil }
            } else {
                Button(L("覚えさせる")) { midi.learn(forCue: cueID) }
                    .help(L("押してから、MIDI コントローラのボタンを押すと、その合図でこのキーが鳴ります"))
            }
            if let b {
                Button { midi.removeBinding(b.id) } label: { Label(L("外す"), systemImage: "xmark") }
            }
        }
    }

    private func sendRow(_ send: MIDISend?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label(L("MIDI を送る"), systemImage: "arrow.up.forward.app")
                    .fixedSize()
                Picker("", selection: Binding(get: { send?.kind },
                                              set: { k in midi.setSend(k.map(MIDISend.make), for: cueID) })) {
                    Text(L("送らない")).tag(MIDISend.Kind?.none)
                    Text(L("ノート")).tag(Optional(MIDISend.Kind.note))
                    Text("CC").tag(Optional(MIDISend.Kind.cc))
                    Text(L("プログラムチェンジ")).tag(Optional(MIDISend.Kind.program))
                    Text("MSC GO").tag(Optional(MIDISend.Kind.mscGo))
                }
                .labelsHidden()
                .frame(maxWidth: 170)
                Spacer(minLength: 4)
                if let send, midi.outputName != nil {
                    Button { midi.transmit(send) } label: { Label(L("試しに送る"), systemImage: "paperplane") }
                }
            }
            if let send { fields(send) }
            if send != nil, midi.outputName == nil {
                Text(L("送る機器が決まっていません（上の帯の「MIDI」で決めます）"))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func fields(_ send: MIDISend) -> some View {
        HStack(spacing: 6) {
            switch send {
            case let .note(ch, n, v):
                channel(ch) { .note(channel: $0, note: n, velocity: v) }
                number(L("ノート"), n, 0...127) { .note(channel: ch, note: $0, velocity: v) }
                Text(MIDINames.note(n)).font(.caption).foregroundStyle(.secondary)
                number(L("強さ"), v, 1...127) { .note(channel: ch, note: n, velocity: $0) }
            case let .cc(ch, n, v):
                channel(ch) { .cc(channel: $0, number: n, value: v) }
                number(L("番号"), n, 0...127) { .cc(channel: ch, number: $0, value: v) }
                number(L("値"), v, 0...127) { .cc(channel: ch, number: n, value: $0) }
            case let .program(ch, n):
                channel(ch) { .program(channel: $0, number: n) }
                // 画面では 1〜128（多くの機材の表示と同じ）
                number(L("番号"), n + 1, 1...128) { .program(channel: ch, number: $0 - 1) }
            case let .mscGo(cue):
                Text(L("キューの番号"))
                TextField("", text: Binding(get: { cue }, set: { midi.setSend(.mscGo(cue: $0), for: cueID) }))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text(L("機器の番号 %d", midi.settings.mscSendID)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func channel(_ ch: Int, _ make: @escaping (Int) -> MIDISend) -> some View {
        number("ch", ch + 1, 1...16) { make($0 - 1) }
    }

    private func number(_ title: String, _ value: Int, _ range: ClosedRange<Int>, _ make: @escaping (Int) -> MIDISend) -> some View {
        HStack(spacing: 4) {
            Text(title)
            TextField("", value: Binding(get: { value }, set: { midi.setSend(make(min(max($0, range.lowerBound), range.upperBound)), for: cueID) }),
                      format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 50)
        }
    }
}

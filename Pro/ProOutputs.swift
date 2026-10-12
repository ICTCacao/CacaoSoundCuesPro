import AppKit
import CacaoSoundCuesCore
import CoreAudio
import SwiftUI

// 出力の系統（Pro 版）。系統 = 機器 ＋ 左右のチャンネル（1-2, 3-4 …）。キー・曲ごとに、どの系統に出すかを選ぶ。
// ミキサーは 1 つのまま、系統ごとに左右を書き分ける（リストの曲のつなぎは系統が違ってもずれない）。
// 別々の機器を使うときは、それらをまとめた機器セット（アグリゲートデバイス。このアプリの中だけ）を作り、1 台の機器として鳴らす。
// 系統の設定（機器）は Mac ごとに違うので、この Mac に保存する。キー・曲の系統は名前でキューシート（pro.json）に保存する

/// 出力の機器（Core Audio）
struct AudioDeviceInfo: Identifiable, Hashable {
    var id: AudioDeviceID
    var uid: String
    var name: String
    var outputChannels: Int
}

enum AudioDevices {
    /// このアプリが作る機器セットの UID の頭（機器の一覧には出さない）
    static let aggregatePrefix = "com.ictcacao.CacaoSoundCuesPro.aggregate."

    /// 出力のある機器（このアプリの機器セットは除く）
    static func outputDevices() -> [AudioDeviceInfo] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            let ch = outputChannels(id)
            guard ch > 0, let uid = string(id, kAudioDevicePropertyDeviceUID), !uid.hasPrefix(aggregatePrefix) else { return nil }
            return AudioDeviceInfo(id: id, uid: uid, name: string(id, kAudioObjectPropertyName) ?? uid, outputChannels: ch)
        }
    }

    /// システムの出力（「サウンド」で選んでいる機器）
    static func defaultOutputUID() -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr else { return nil }
        return string(id, kAudioDevicePropertyDeviceUID)
    }

    static func outputChannels(_ id: AudioDeviceID) -> Int {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    static func sampleRate(_ id: AudioDeviceID) -> Double {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var sr: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &sr)
        return sr
    }

    static func setSampleRate(_ id: AudioDeviceID, _ sr: Double) {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var value = Float64(sr)
        AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float64>.size), &value)
    }

    /// 機器セットを作る（このアプリの中だけ。アプリを終えると消える）。最初の機器の時計に合わせ、ほかはずれを補正する
    static func createAggregate(_ uids: [String]) -> AudioDeviceID? {
        let subs: [[String: Any]] = uids.enumerated().map { i, uid in
            [kAudioSubDeviceUIDKey: uid, kAudioSubDeviceDriftCompensationKey: i == 0 ? 0 : 1]
        }
        let desc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "CacaoSoundCuesPro",
            kAudioAggregateDeviceUIDKey: aggregatePrefix + UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceSubDeviceListKey: subs,
            kAudioAggregateDeviceMainSubDeviceKey: uids[0],
        ]
        var id = AudioDeviceID(0)
        guard AudioHardwareCreateAggregateDevice(desc as CFDictionary, &id) == noErr, id != 0 else { return nil }
        return id
    }

    static func destroyAggregate(_ id: AudioDeviceID) {
        AudioHardwareDestroyAggregateDevice(id)
    }
}

/// 出力の系統
struct OutputBus: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    /// 機器（nil ならシステムの出力）
    var deviceUID: String?
    /// 左右のチャンネルの組（0 なら 1-2、1 なら 3-4 …）
    var pair: Int = 0
}

@MainActor @Observable
final class ProOutputs {
    static let shared = ProOutputs()
    private static let storageKey = "pro.outputs"
    static let mainName = L("メイン")

    /// 系統（最初がメイン）。この Mac に保存
    var buses: [OutputBus] {
        didSet {
            if let d = try? JSONEncoder().encode(buses) { UserDefaults.standard.set(d, forKey: Self.storageKey) }
        }
    }
    /// 出力のある機器
    private(set) var devices: [AudioDeviceInfo] = []
    /// いま鳴らしている機器の説明（設定の画面に出す）
    private(set) var summary = ""

    /// 当てている形（同じなら当て直さない。機器セットを作ると機器の一覧が変わるため、くり返さないように）
    private struct Plan: Equatable {
        var uids: [String]
        var channels: [AudioOutput.BusChannels]
    }
    private var applied: Plan?
    /// 始められなかった形（機器の抜き差しの知らせでは試し直さない。設定を変えたときに試し直す）
    private var failed: Plan?
    private var aggregate: AudioDeviceID?
    private var listening = false

    private init() {
        if let d = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([OutputBus].self, from: d), !saved.isEmpty {
            buses = saved
        } else {
            buses = [OutputBus(name: Self.mainName)]
        }
        devices = AudioDevices.outputDevices()
    }

    // MARK: キー・曲の系統

    /// キー・曲（tag）の系統の番号。選んでいない・この Mac に無い名前ならメイン（0）
    func bus(for tag: UUID) -> Int {
        guard let name = ProModel.shared.data.outputs[tag.uuidString] else { return 0 }
        return buses.firstIndex { $0.name == name } ?? 0
    }

    /// キー・曲の系統の名前（nil ならメイン）
    func busName(for cueID: UUID) -> String? { ProModel.shared.data.outputs[cueID.uuidString] }

    func setBus(_ name: String?, for cueID: UUID) {
        ProModel.shared.setOutput(cueID, (name == nil || name == buses.first?.name) ? nil : name)
    }

    // MARK: 系統の設定

    func addBus() {
        var n = buses.count
        var name = L("系統%d", n)
        while buses.contains(where: { $0.name == name }) { n += 1; name = L("系統%d", n) }
        buses.append(OutputBus(name: name, deviceUID: buses.first?.deviceUID))
        apply(force: true)
    }

    func removeBus(_ id: UUID) {
        guard buses.first?.id != id else { return }
        buses.removeAll { $0.id == id }
        apply(force: true)
    }

    /// 名前を変える。開いているキューシートのキー・曲の指定も付け替える
    func rename(_ id: UUID, to newName: String) {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard let i = buses.firstIndex(where: { $0.id == id }), !name.isEmpty,
              !buses.contains(where: { $0.id != id && $0.name == name }) else { return }
        let old = buses[i].name
        buses[i].name = name
        ProModel.shared.renameOutput(old, to: name)
    }

    func setDevice(_ id: UUID, uid: String?) {
        guard let i = buses.firstIndex(where: { $0.id == id }) else { return }
        buses[i].deviceUID = uid
        buses[i].pair = min(buses[i].pair, max(0, pairCount(uid) - 1))
        apply(force: true)
    }

    func setPair(_ id: UUID, _ pair: Int) {
        guard let i = buses.firstIndex(where: { $0.id == id }) else { return }
        buses[i].pair = pair
        apply(force: true)
    }

    /// 機器の左右の組の数（2ch なら 1）
    func pairCount(_ uid: String?) -> Int {
        guard let d = device(uid) else { return 1 }
        return max(1, d.outputChannels / 2)
    }

    func device(_ uid: String?) -> AudioDeviceInfo? {
        let u = uid ?? AudioDevices.defaultOutputUID()
        return devices.first { $0.uid == u }
    }

    func deviceName(_ uid: String?) -> String {
        guard let uid else { return L("システムの出力（%@）", device(nil)?.name ?? "?") }
        return devices.first { $0.uid == uid }?.name ?? L("%@（つながっていません）", uid)
    }

    // MARK: 当てる

    /// 系統の設定を出力に当てる。メインだけでシステムの出力の 1-2 なら、無料版と同じ出し方に戻す。
    /// force: 設定を変えたとき（始められなかった形も試し直す）
    func apply(force: Bool = false) {
        listen()
        devices = AudioDevices.outputDevices()
        let output = AppModel.shared.output
        let defaultUID = AudioDevices.defaultOutputUID()
        if buses.count == 1, buses[0].deviceUID == nil, buses[0].pair == 0 {
            applied = nil
            summary = ""
            output.route(nil)
            dropAggregate()
            return
        }
        // 使う機器（メインの機器が先頭。時計はメインの機器に合わせる）。つながっていない機器はメインへ
        var uids: [String] = []
        for b in buses {
            if let u = b.deviceUID ?? defaultUID, devices.contains(where: { $0.uid == u }), !uids.contains(u) { uids.append(u) }
        }
        guard !uids.isEmpty else {
            applied = nil
            output.route(nil)
            dropAggregate()
            return
        }
        // 機器セットでは、チャンネルは機器の順に続けて並ぶ
        var offsets: [String: Int] = [:]
        var total = 0
        for u in uids {
            offsets[u] = total
            total += devices.first { $0.uid == u }?.outputChannels ?? 0
        }
        let channels: [AudioOutput.BusChannels] = buses.map { b in
            guard let u = b.deviceUID ?? defaultUID, let off = offsets[u], let d = devices.first(where: { $0.uid == u }),
                  b.pair * 2 + 1 < d.outputChannels else { return .init(left: 0, right: 1) }
            return .init(left: off + b.pair * 2, right: off + b.pair * 2 + 1)
        }
        let plan = Plan(uids: uids, channels: channels)
        guard plan != applied else { return }
        if !force, plan == failed { return }
        failed = nil
        applied = plan

        if uids.count == 1, let d = devices.first(where: { $0.uid == uids[0] }) {
            dropAggregate()
            summary = d.name
            output.route(.init(device: d.id, buses: channels))
            checkStarted(d.name, plan)
            return
        }
        // 別々の機器: サンプルレートをメインの機器にそろえてから、機器セットを作る
        let ids = uids.compactMap { u in devices.first { $0.uid == u }?.id }
        let rate = AudioDevices.sampleRate(ids[0])
        for id in ids.dropFirst() where rate > 0 && AudioDevices.sampleRate(id) != rate { AudioDevices.setSampleRate(id, rate) }
        dropAggregate()
        guard let agg = AudioDevices.createAggregate(uids) else {
            summary = L("機器セットを作れませんでした。メインの機器だけで鳴らします")
            if let d = devices.first(where: { $0.uid == uids[0] }) {
                output.route(.init(device: d.id, buses: channels.map { $0.right < d.outputChannels ? $0 : .init(left: 0, right: 1) }))
            }
            return
        }
        aggregate = agg
        summary = uids.compactMap { u in devices.first { $0.uid == u }?.name }.joined(separator: " ＋ ")
        // 機器セットはでき上がるまで少しかかる（チャンネル数が決まるまで待つ）
        let name = summary
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard self.aggregate == agg else { return }
            output.route(.init(device: agg, buses: channels))
            self.checkStarted(name, plan)
        }
    }

    /// 決めた機器で始められず、システムの出力に戻ったとき
    private func checkStarted(_ name: String, _ plan: Plan) {
        let output = AppModel.shared.output
        guard output.routing == nil, let err = output.lastError else { return }
        summary = L("「%@」で鳴らせなかったので、システムの出力で鳴らしています（%@）", name, err)
        // 次に設定を変えたときに、もう一度試す（機器セットを消すと機器の一覧の知らせが来るが、そこでは試し直さない）
        applied = nil
        failed = plan
        dropAggregate()
    }

    private func dropAggregate() {
        if let a = aggregate {
            aggregate = nil
            AudioDevices.destroyAggregate(a)
        }
    }

    /// 機器を抜き差ししたとき・システムの出力を変えたときに当て直す
    private func listen() {
        guard !listening else { return }
        listening = true
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { _, _ in
                MainActor.assumeIsolated {
                    // 機器セットを作ったときにも呼ばれるが、形が同じなら apply は何もしない
                    ProOutputs.shared.apply()
                }
            }
        }
    }
}

// MARK: - 画面

/// 上の帯の「出力」から開く、系統の設定
struct OutputsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    private var outputs: ProOutputs { ProOutputs.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("出力の系統")).font(.title3.bold())
            Text(L("系統ごとに、鳴らす機器と左右のチャンネルを決めます。キー・リストの曲は、インスペクタで系統を選びます（選ばなければメイン）。別々の機器を選ぶと、まとめて 1 台のように鳴らします（時計のずれは macOS が補正）。この設定はこの Mac に保存されます。"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text(L("系統")).font(.caption.bold())
                    Text(L("機器")).font(.caption.bold())
                    Text(L("チャンネル")).font(.caption.bold())
                    Text("")
                }
                ForEach(Array(outputs.buses.enumerated()), id: \.element.id) { index, bus in
                    GridRow {
                        TextField("", text: Binding(get: { bus.name }, set: { outputs.rename(bus.id, to: $0) }))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                        Picker("", selection: Binding(get: { bus.deviceUID }, set: { outputs.setDevice(bus.id, uid: $0) })) {
                            Text(outputs.deviceName(nil)).tag(String?.none)
                            ForEach(outputs.devices) { d in
                                Text(L("%@（%dch）", d.name, d.outputChannels)).tag(Optional(d.uid))
                            }
                            if let uid = bus.deviceUID, !outputs.devices.contains(where: { $0.uid == uid }) {
                                Text(outputs.deviceName(uid)).tag(Optional(uid))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 280)
                        Picker("", selection: Binding(get: { bus.pair }, set: { outputs.setPair(bus.id, $0) })) {
                            ForEach(0..<outputs.pairCount(bus.deviceUID), id: \.self) { p in
                                Text("\(p * 2 + 1)-\(p * 2 + 2)").tag(p)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                        if index == 0 {
                            Text(L("（いつもある）")).font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button { outputs.removeBus(bus.id) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                                .help(L("この系統を消す（この系統を選んでいたキー・曲はメインで鳴る）"))
                        }
                    }
                }
            }
            HStack {
                Button { outputs.addBus() } label: { Label(L("系統を足す"), systemImage: "plus") }
                Spacer()
                if !outputs.summary.isEmpty {
                    Text(L("鳴らしている機器: %@", outputs.summary))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(L("閉じる")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 640)
        .disabled(model.showMode)
    }
}

/// インスペクタの「出力」の行（系統が 2 つ以上あるとき）
struct ProOutputRow: View {
    @Environment(AppModel.self) private var model
    let cueID: UUID
    private var outputs: ProOutputs { ProOutputs.shared }

    var body: some View {
        if outputs.buses.count > 1 {
            HStack(spacing: 8) {
                Label(L("出力"), systemImage: "hifispeaker.2")
                    .fixedSize()
                Picker("", selection: Binding(get: { outputs.busName(for: cueID) ?? outputs.buses[0].name },
                                              set: { outputs.setBus($0, for: cueID) })) {
                    ForEach(outputs.buses) { b in Text(b.name).tag(b.name) }
                    // この Mac に無い系統の名前（別の Mac で選んだもの）
                    if let name = outputs.busName(for: cueID), !outputs.buses.contains(where: { $0.name == name }) {
                        Text(L("%@（この Mac に無い → メイン）", name)).tag(name)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
                .disabled(model.showMode)
                Spacer()
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.08)))
        }
    }
}

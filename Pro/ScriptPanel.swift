import AppKit
import CacaoSoundCuesCore
import SwiftUI

// 台本のパネル。台本を目で追いながら、自分でページを送る（← → ／ 下の ‹ ›）。
// 台本の文字には何も載せず（紙の台本と同じ見た目）、ページの下（横書きは右）の「きっかけの帯」に、
// きっかけの位置から線を引き、押すキー・名前・メモを横書きで出す（音響台本の書き方）。次のページにきっかけがあれば下に出す

/// 主画面の横に台本のパネルを並べる。
/// 開く・畳むで主画面の入れ物が変わらないよう、HSplitView は使わずに自分で並べる（畳んだら主画面が台本のぶんまで広がる）。
/// 主画面は、出しているパネル（キーの一覧・リスト・音源設定）がそれぞれ最小の幅で入るところまで狭められる。
/// それより台本を広げると主画面を隠し、台本を窓いっぱいに出す
struct ProScriptSplit<Content: View>: View {
    @ViewBuilder var content: Content
    private var pro: ProModel { ProModel.shared }
    /// 台本のパネルの幅（窓の幅に対する割合。1 なら窓いっぱい。この Mac に保存）
    @AppStorage("pro.scriptFraction") private var fraction = 0.3
    @AppStorage("showKeyboard") private var showKeyboard = true
    @AppStorage("showInspector") private var showInspector = true
    @AppStorage("showKeypad") private var showKeypad = false
    @AppStorage("keyboardScale") private var keyboardScale = 1.0
    @State private var dragStart: CGFloat?

    private var minScript: CGFloat { 280 }
    /// 仕切りの太さ（つかむところ）
    private var handle: CGFloat { 7 }

    /// 主画面の最小の幅（MainView の各パネルの minWidth と、キーボードがいちばん小さくなったときの幅）
    private var minContent: CGFloat {
        let divider: CGFloat = 1
        if showKeyboard {
            let columns: CGFloat = 13 + (showKeypad ? 4 : 0)
            let keyboard = 44 * min(keyboardScale, 1) * columns + 5 * (columns - 1) + (showKeypad ? 22 : 0) + 40
            return max(keyboard, showInspector ? 400 + divider + 480 : 400)
        }
        return showInspector ? 260 + 380 + 460 + divider * 2 : 260 + 380 + divider
    }

    var body: some View {
        GeometryReader { geo in
            let total = geo.size.width
            let width = scriptWidth(total: total)
            let full = width >= total - handle
            HStack(spacing: 0) {
                if pro.showPanel {
                    ScriptPanel()
                        .frame(width: max(0, width))
                    divider(total: total)
                } else {
                    // 畳んだときは左に細い帯を残し、押すと開く
                    FoldedScriptStrip()
                    Rectangle().fill(Theme.divider).frame(width: 1)
                }
                // 台本を窓いっぱいにしたときは、主画面を隠す（キー操作は窓で受けるので鳴らせる）
                content
                    .frame(minWidth: full && pro.showPanel ? 0 : minContent, maxWidth: .infinity, maxHeight: .infinity)
                    .frame(width: full && pro.showPanel ? 0 : nil)
                    .clipped()
                    .opacity(full && pro.showPanel ? 0 : 1)
                    .allowsHitTesting(!(full && pro.showPanel))
            }
        }
    }

    /// 台本の幅。主画面が最小の幅より狭くなるところまで広げたら、窓いっぱい
    private func scriptWidth(total: CGFloat) -> CGFloat {
        let maxSide = total - handle - minContent
        let w = CGFloat(fraction) * total
        if fraction >= 0.999 || w > maxSide { return w > maxSide + minContent / 2 || fraction >= 0.999 ? total - handle : max(minScript, maxSide) }
        return max(minScript, w)
    }

    /// ドラッグで幅を変える仕切り。主画面の最小の幅を越えて半分以上引っぱると、台本を窓いっぱいに
    private func divider(total: CGFloat) -> some View {
        ZStack {
            Color.clear
            Rectangle().fill(Theme.divider).frame(width: 1)
        }
        .frame(width: handle)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { v in
                    guard total > 0 else { return }
                    let start = dragStart ?? scriptWidth(total: total)
                    if dragStart == nil { dragStart = start }
                    let w = start + v.translation.width
                    let maxSide = total - handle - minContent
                    if w > maxSide + minContent / 2 {
                        fraction = 1
                    } else {
                        fraction = Double(min(max(w, minScript), max(minScript, maxSide)) / total)
                    }
                }
                .onEnded { _ in dragStart = nil }
        )
        .help(L("ドラッグで台本の幅を変える（右端まで引くと台本を窓いっぱいに）"))
    }
}

/// 畳んだ台本のパネル（左の細い帯）
private struct FoldedScriptStrip: View {
    private var pro: ProModel { ProModel.shared }

    var body: some View {
        Button { pro.showPanel = true } label: {
            VStack(spacing: 10) {
                Image(systemName: "chevron.right")
                Image(systemName: "text.book.closed")
                Text(L("台本"))
                    .font(.caption)
                Spacer()
            }
            .padding(.top, 12)
            .frame(width: 28)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Theme.panel)
        .help(L("台本のパネルを開く"))
    }
}

/// 上の帯に足すボタン（台本のパネルの表示）
struct ProTopBarItems: View {
    private var pro: ProModel { ProModel.shared }

    var body: some View {
        @Bindable var pro = pro
        Toggle(isOn: $pro.showPanel) {
            Label(L("台本"), systemImage: "text.book.closed")
        }
        .toggleStyle(.button)
        .help(L("台本（ScenarioWriterSolo）のパネルを出す・畳む"))
    }
}

struct ScriptPanel: View {
    @Environment(AppModel.self) private var model
    private var pro: ProModel { ProModel.shared }

    var body: some View {
        VStack(spacing: 0) {
            header
            ThemeDivider()
            if let script = pro.displayScript {
                GeometryReader { geo in
                    ScriptPager(script: script,
                                size: geo.size,
                                vertical: pro.data.vertical,
                                fontSize: pro.data.fontSize,
                                lineSpacing: pro.data.lineSpacing,
                                charSpacing: pro.data.charSpacing,
                                links: pro.data.links,
                                marks: pro.allMarks(),
                                notes: pro.data.notes,
                                active: pro.activeCueIDs,
                                selected: pro.selected,
                                keyCues: model.show.keyCues,
                                sequences: model.show.sequences,
                                page: pro.page)
                }
                .background(Color(nsColor: .textBackgroundColor))
                ThemeDivider()
                // 鳴っている音の波形（高さは変えない。変わると台本の広さが変わって組み直しになるため）
                PlayingWaveStrip()
                    .frame(height: 44)
                ThemeDivider()
                footer(script)
            } else {
                empty
            }
        }
        .background(Theme.panel)
        // 「自動でページを送る」が ON なら、Standby が移ったときにそのきっかけのページへ
        .onChange(of: standbyLine) { _, uid in
            if pro.data.autoFollow, let uid { pro.revealRequest = uid }
        }
    }

    /// Standby の曲が結びついている台本の行
    private var standbyLine: String? {
        guard let seqID = model.activeSequenceID, let seq = model.show.sequences.first(where: { $0.id == seqID }),
              let i = model.upcomingIndex(seqID), seq.steps.indices.contains(i) else { return nil }
        return pro.anchor(for: seq.steps[i].id)?.line
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.book.closed")
            Text(pro.script.map { $0.title.isEmpty ? L("台本") : $0.title } ?? L("台本"))
                .font(.headline)
                .lineLimit(1)
            Spacer()
            if pro.script != nil {
                // 縦書き・横書きの切り替え（ScenarioWriterSolo の「縦書き / 横書き」ボタンと同じ）
                Picker("", selection: Binding(get: { pro.data.vertical }, set: { pro.setVertical($0) })) {
                    Text(L("縦")).tag(true)
                    Text(L("横")).tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help(L("台本を縦書き・横書きで表示"))
            }
            Menu {
                Button { pro.importScript() } label: { Label(L("台本を取り込む…"), systemImage: "square.and.arrow.down") }
                if pro.script != nil {
                    Button { pro.reloadScript() } label: { Label(L("台本を読み込み直す"), systemImage: "arrow.clockwise") }
                    Divider()
                    Toggle(L("縦書き"), isOn: Binding(get: { pro.data.vertical }, set: { pro.setVertical($0) }))
                    Toggle(L("Standby のきっかけへ自動でページを送る"), isOn: Binding(get: { pro.data.autoFollow }, set: { pro.setAutoFollow($0) }))
                    // 文字の大きさは上限。1 行（人物名欄 ＋ 本文の字数）が入りきらないときは小さくなる
                    Menu(L("文字の大きさ")) {
                        ForEach([12.0, 14, 16, 18, 20, 24, 28, 32], id: \.self) { s in
                            Button { pro.setFontSize(s) } label: {
                                Text("\(Int(s))") + Text(pro.data.fontSize == s ? " ✓" : "")
                            }
                        }
                    }
                    // 1 行の字数（ふだんは台本〈ScenarioWriterSolo の書式〉のとおり。このキューシートだけ変えられる）
                    Menu(L("人物名欄の字数")) {
                        Button { pro.setNameChars(nil) } label: {
                            Text(L("台本のとおり（%d）", pro.script?.characterLength ?? 0)) + Text(pro.data.nameChars == nil ? " ✓" : "")
                        }
                        Divider()
                        ForEach(Array(2...12), id: \.self) { n in
                            Button { pro.setNameChars(n) } label: { Text("\(n)") + Text(pro.data.nameChars == n ? " ✓" : "") }
                        }
                    }
                    Menu(L("本文 1 行の字数")) {
                        Button { pro.setBodyChars(nil) } label: {
                            Text(L("台本のとおり（%d）", pro.script?.bodyLength ?? 0)) + Text(pro.data.bodyChars == nil ? " ✓" : "")
                        }
                        Divider()
                        ForEach([15, 20, 24, 25, 28, 30, 32, 35, 36, 40, 45, 50, 60], id: \.self) { n in
                            Button { pro.setBodyChars(n) } label: { Text("\(n)") + Text(pro.data.bodyChars == n ? " ✓" : "") }
                        }
                    }
                    Menu(L("行間")) {
                        ForEach([(0.0, L("なし")), (0.2, L("標準")), (0.5, L("広い")), (0.8, L("もっと広い")), (1.2, L("とても広い"))], id: \.0) { v, name in
                            Button { pro.setLineSpacing(v) } label: {
                                Text(name) + Text(abs(pro.data.lineSpacing - v) < 0.001 ? " ✓" : "")
                            }
                        }
                    }
                    Menu(L("文字間")) {
                        ForEach([(-0.05, L("詰める")), (0.0, L("標準")), (0.1, L("少し空ける")), (0.2, L("空ける")), (0.4, L("広く空ける"))], id: \.0) { v, name in
                            Button { pro.setCharSpacing(v) } label: {
                                Text(name) + Text(abs(pro.data.charSpacing - v) < 0.001 ? " ✓" : "")
                            }
                        }
                    }
                    Divider()
                    Button(role: .destructive) { pro.removeScript() } label: { Label(L("台本を外す"), systemImage: "xmark") }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(model.showMode && pro.script == nil)
            Button { pro.showPanel = false } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
                .help(L("台本のパネルを左に畳む"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Text(L("ScenarioWriterSolo の台本（.scwd）を取り込むと、ここに台本が出ます。\nキーやリストの曲を、台本の行（きっかけ）に結びつけられます。"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button { pro.importScript() } label: { Label(L("台本を取り込む…"), systemImage: "square.and.arrow.down") }
                .disabled(model.showMode)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 下の帯: ページ送りと、次のページのきっかけ
    private func footer(_ script: ScriptDocument) -> some View {
        let next = nextPageMarks
        let vertical = pro.data.vertical
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // 縦書きは本と同じく左が次のページ
                Button { pro.turn(vertical ? 1 : -1) } label: { Image(systemName: "chevron.left") }
                    .disabled(vertical ? pro.page >= pro.pageCount - 1 : pro.page <= 0)
                Text("\(pro.page + 1) / \(max(pro.pageCount, 1))")
                    .monospacedDigit()
                    .frame(minWidth: 60)
                Button { pro.turn(vertical ? -1 : 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(vertical ? pro.page <= 0 : pro.page >= pro.pageCount - 1)
                Text(L("← → でページ送り"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            // 「次のページ」の行は、無くても場所を取っておく（帯の高さが変わると台本の広さが変わり、
            // ページの区切りが変わって「次のページ」が出たり消えたりをくり返し、固まるため）
            HStack(spacing: 6) {
                if !next.isEmpty {
                    Text(L("次のページ"))
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .background(Capsule().fill(Color.orange.opacity(0.3)))
                    ForEach(next) { m in
                        MarkBadge(mark: m, lit: pro.activeCueIDs.contains(m.id))
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(height: 20)
            .clipped()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// 次のページにあるきっかけ（台本のパネルがページの行を教える）
    private var nextPageMarks: [CueMark] {
        ScriptPageIndex.shared.lines(onPage: pro.page + 1).flatMap { pro.marks(for: $0) }
    }
}

/// 鳴っている音の波形。横に長く、高さは抑える。鳴っている音が複数なら段に分ける（最大 3。新しいものが上）。
/// 再生範囲の外はうすく、鳴り終えたところは明るく、いまの位置に線。右に残り時間
struct PlayingWaveStrip: View {
    @Environment(AppModel.self) private var model

    private struct Voice: Identifiable {
        var id: UInt64
        var label: String
        var name: String
        var color: Color
        var peaks: [Float]
        var frames: Int
        var status: VoiceStatus
        var sampleRate: Double
    }

    private var voices: [Voice] {
        var out: [Voice] = []
        for st in model.status.reversed() where !st.armed {
            var label = "", name = "", color = Color.gray, soundID: UUID?
            if let cue = model.show.keyCues.first(where: { $0.id == st.tag }) {
                label = KeyboardLayout.label(cue.keyCode)
                name = cue.name
                color = AppModel.colors[cue.colorIndex % AppModel.colors.count]
                soundID = cue.play.soundID
            } else {
                for seq in model.show.sequences {
                    if let i = seq.steps.firstIndex(where: { $0.id == st.tag }) {
                        label = "≡\(i + 1)"
                        name = seq.steps[i].name
                        color = Color(nsColor: .systemIndigo)
                        soundID = seq.steps[i].play.soundID
                        break
                    }
                }
            }
            guard let soundID, let b = model.buffers[soundID] else { continue }
            out.append(Voice(id: st.token, label: label, name: name, color: color, peaks: b.peaks, frames: b.frames,
                             status: st, sampleRate: b.sampleRate))
            if out.count == 3 { break }
        }
        return out
    }

    var body: some View {
        let list = voices
        VStack(spacing: 2) {
            if list.isEmpty {
                Text(L("再生中の音はありません"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(list) { v in row(v) }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.25))
    }

    private func row(_ v: Voice) -> some View {
        let st = v.status
        let remaining = Double(max(0, st.remainingFrames)) / max(v.sampleRate, 1)
        return HStack(spacing: 6) {
            Text(v.label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 3).fill(v.color))
                .help(v.name)
            Canvas { ctx, size in
                guard !v.peaks.isEmpty, v.frames > 0, size.width > 0 else { return }
                let mid = size.height / 2
                let frames = Double(v.frames)
                func x(_ f: Int) -> CGFloat { CGFloat(Double(f) / frames) * size.width }
                let xs = x(st.startFrame), xe = x(st.endFrame > 0 ? st.endFrame : v.frames), xp = x(st.position)
                let cols = Int(size.width)
                for c in 0..<max(cols, 1) {
                    let a = c * v.peaks.count / max(cols, 1)
                    let b = max(a + 1, (c + 1) * v.peaks.count / max(cols, 1))
                    var m: Float = 0
                    for k in a..<min(b, v.peaks.count) { m = max(m, v.peaks[k]) }
                    let h = max(1, CGFloat(m) * size.height * 0.95)
                    let cx = CGFloat(c) + 0.5
                    let inRange = cx >= xs && cx <= xe
                    let played = cx <= xp
                    let opacity = !inRange ? 0.15 : (played ? 0.95 : 0.45)
                    ctx.fill(Path(CGRect(x: CGFloat(c), y: mid - h / 2, width: 1, height: h)),
                             with: .color(v.color.opacity(opacity)))
                }
                // いまの位置
                ctx.fill(Path(CGRect(x: xp - 0.75, y: 0, width: 1.5, height: size.height)), with: .color(.white))
            }
            Text(st.loop ? "∞" : remaining.timeText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(st.stopping ? .orange : .secondary)
                .frame(width: 52, alignment: .trailing)
        }
        .frame(maxHeight: .infinity)
    }
}

/// 札（SwiftUI で使う。キーボードの色と同じ）
struct MarkBadge: View {
    let mark: CueMark
    var lit = false

    var body: some View {
        Text(mark.label)
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .padding(.horizontal, 5)
            .frame(minHeight: 20)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: mark.color).opacity(lit ? 0.95 : 0.5)))
            .help(mark.name)
    }
}

/// どのページにどの行があるか（台本のパネルが組んだ結果。下の帯の「次のページ」に使う）
@MainActor @Observable
final class ScriptPageIndex {
    static let shared = ScriptPageIndex()
    var pages: [[String]] = []
    func lines(onPage p: Int) -> [String] { pages.indices.contains(p) ? pages[p] : [] }
    func page(of uid: String) -> Int? { pages.firstIndex { $0.contains(uid) } }
}

// MARK: - ページを組む（AppKit のテキストの仕組みで、縦書きも横書きもページに分ける）

private extension NSAttributedString.Key {
    static let scriptLine = NSAttributedString.Key("CacaoScriptLine")
    static let scriptPiece = NSAttributedString.Key("CacaoScriptPiece")
}

struct ScriptPager: NSViewRepresentable {
    let script: ScriptDocument
    let size: CGSize
    let vertical: Bool
    let fontSize: Double
    let lineSpacing: Double
    let charSpacing: Double
    let links: [String: CueAnchor]
    /// 帯に描くきっかけ（始まり・終わり・メモ）
    let marks: [CueMark]
    let notes: [ScriptNote]
    let active: Set<UUID>
    let selected: CueAnchor?
    let keyCues: [KeyCue]
    let sequences: [CueSequence]
    let page: Int

    func makeNSView(context: Context) -> PagerView { PagerView() }

    func updateNSView(_ view: PagerView, context: Context) {
        let pro = ProModel.shared
        // 組み直しが要るのは、台本・大きさ・書き方向・文字の大きさが変わったとき（きっかけは帯に描くだけなので組み直さない）
        let layoutKey = LayoutKey(script: script, size: size, vertical: vertical, fontSize: fontSize,
                                  lineSpacing: lineSpacing, charSpacing: charSpacing)
        // 大きさだけが変わったとき（窓や仕切りを動かしている最中）は、止まってから 1 回だけ組み直す
        if let old = view.layoutKey, old != layoutKey, old.size != layoutKey.size,
           LayoutKey(script: old.script, size: layoutKey.size, vertical: old.vertical, fontSize: old.fontSize,
                     lineSpacing: old.lineSpacing, charSpacing: old.charSpacing) == layoutKey {
            view.scheduleRebuild(layoutKey)
            view.applyHighlight(selected: selected)
            return
        }
        if view.layoutKey != layoutKey {
            view.build(layoutKey)
            let count = view.pageCount
            // 画面を描いている最中に状態を変えないよう、次の回にまわす
            DispatchQueue.main.async {
                pro.pageCount = count
                if pro.page >= count { pro.page = max(0, count - 1) }
            }
        }
        view.applyHighlight(selected: selected)
        if let uid = pro.revealRequest {
            DispatchQueue.main.async {
                pro.revealRequest = nil
                if let p = ScriptPageIndex.shared.page(of: uid), p != pro.page { pro.page = p }
            }
        }
        view.show(page: min(pro.page, max(0, view.pageCount - 1)), marks: marks, notes: notes, active: active)
    }

    struct LayoutKey: Equatable {
        var script: ScriptDocument
        var size: CGSize
        var vertical: Bool
        var fontSize: Double
        var lineSpacing: Double
        var charSpacing: Double
    }
}

/// 文章の中の、台本の本文のかたまり（行の uid と、そのかたまりが本文の何文字目から始まるか）
private final class TextPiece: NSObject {
    let line: String
    let base: Int
    init(line: String, base: Int) {
        self.line = line
        self.base = base
    }
}

/// 台本のページを表示する。ページごとに NSTextView を作り、同じ文章を順に流し込む。
/// 1 行は ScenarioWriterSolo の書式どおり「人物名欄 ＋ 本文」の文字数で折り返す（紙の台本と同じ折り返し）。
/// パネルに 1 行が入りきらないときは、文字を小さくして収める。ページの下（横書きは右）は、きっかけの帯
final class PagerView: NSView {
    var layoutKey: ScriptPager.LayoutKey?
    private let storage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private var textViews: [ScriptTextView] = []
    private var pageRanges: [NSRange] = []
    /// ページごとのきっかけの帯
    private var bands: [CueBandView] = []
    /// いま画面に出しているページ（見えている 1〜2 ページだけ並べる）
    private var attached = Set<Int>()
    /// 行の uid → 文章の中の範囲・本文の始まり
    private var lineRanges: [String: NSRange] = [:]
    private var textStarts: [String: Int] = [:]
    private var lastSelected: CueAnchor?
    private var selectedRanges: [NSRange] = []
    private var pageSize = CGSize(width: 100, height: 100)
    private let inset: CGFloat = 16
    /// きっかけの帯の太さ（縦書きは高さ、横書きは幅）
    private var bandThickness: CGFloat = 0
    /// 実際に使う文字の大きさ（1 行が入りきらないときは小さくする）
    private(set) var fontSize: Double = 16
    /// 大きさが変わったあと、少し待ってから組み直す
    private var pendingKey: ScriptPager.LayoutKey?
    private var rebuildWork: DispatchWorkItem?

    func scheduleRebuild(_ key: ScriptPager.LayoutKey) {
        pendingKey = key
        rebuildWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let key = self.pendingKey else { return }
            self.pendingKey = nil
            MainActor.assumeIsolated { self.rebuildNow(key) }
        }
        rebuildWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// 組み直して、今のページとページ数を知らせる
    private func rebuildNow(_ key: ScriptPager.LayoutKey) {
        guard key != layoutKey else { return }
        let pro = ProModel.shared
        build(key)
        let count = pageCount
        pro.pageCount = count
        if pro.page >= count { pro.page = max(0, count - 1) }
        show(page: min(pro.page, max(0, count - 1)), marks: lastMarks, notes: lastNotes, active: lastActive)
    }

    var pageCount: Int { textViews.count }

    // MARK: スクロール（ページを一列に並べ、巻物のように流す）

    private var vertical: Bool { layoutKey?.vertical ?? true }
    /// 1 ページの長さ（縦書きは幅、横書きは高さ。ページはこの向きに並ぶ）
    private var pageLength: CGFloat { max(1, vertical ? pageSize.width : pageSize.height) }
    private var maxOffset: CGFloat { CGFloat(max(0, textViews.count - 1)) * pageLength }
    /// どこまで流したか（0 で 1 ページ目がちょうど見える。1 ページ流すと pageLength）
    private var offset: CGFloat = 0
    /// 組み直した直後は、目当てのページへ動かさずに飛ぶ
    private var justBuilt = false
    /// ← → などで、目当ての位置へなめらかに流しているとき
    private var animTarget: CGFloat?
    private var animTimer: Timer?
    /// ProModel に知らせたページ
    private var reportedPage = -1
    private var lastMarks: [CueMark] = []
    /// きっかけ → 帯の段（台本全体で決める）
    private var laneOf: [UUID: Int] = [:]
    private var lanesDirty = true
    private var lastNotes: [ScriptNote] = []
    private var lastActive: Set<UUID> = []

    /// いま主に見えているページ
    var currentPage: Int { min(max(Int((offset / pageLength).rounded()), 0), max(0, textViews.count - 1)) }

    /// マウスのホイール・横スクロール（チルト・横のダイヤル）、トラックパッドで流す。止めたところで止まる。
    /// 中身を動かす向きで決める: 縦書きはページが左へ進むので、中身が右へ動く向きが先。縦のホイールは下へが先
    override func scrollWheel(with event: NSEvent) {
        guard !textViews.isEmpty else { return }
        var dx = event.scrollingDeltaX
        var dy = event.scrollingDeltaY
        // マウスのホイールは行の単位なので、点の単位に直す
        if !event.hasPreciseScrollingDeltas { dx *= 40; dy *= 40 }
        let d = vertical ? dx - dy : -dx - dy
        guard d != 0 else { return }
        stopAnimation()
        setOffset(offset + d)
        reportPage()
    }

    private func setOffset(_ value: CGFloat) {
        offset = min(max(value, 0), maxOffset)
        layoutPages(refreshAll: false)
    }

    /// 流した結果のページを ProModel に知らせる（下の「n / N」と「次のページ」のため）
    private func reportPage() {
        let p = currentPage
        guard p != reportedPage else { return }
        reportedPage = p
        DispatchQueue.main.async { MainActor.assumeIsolated { if ProModel.shared.page != p { ProModel.shared.page = p } } }
    }

    private func animate(to target: CGFloat) {
        animTarget = min(max(target, 0), maxOffset)
        guard animTimer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.stepAnimation() }
        }
        RunLoop.main.add(t, forMode: .common)
        animTimer = t
    }

    private func stepAnimation() {
        guard let target = animTarget else { return stopAnimation() }
        let diff = target - offset
        if abs(diff) < 0.5 {
            setOffset(target)
            stopAnimation()
            reportPage()
        } else {
            setOffset(offset + diff * 0.25)
        }
    }

    private func stopAnimation() {
        animTimer?.invalidate()
        animTimer = nil
        animTarget = nil
    }

    /// ページの境の線
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        for i in attached where i > 0 {
            let f = textViews[i].frame
            // 縦書きは前のページが右、横書きは上
            if vertical { NSRect(x: f.maxX - 0.5, y: 0, width: 1, height: bounds.height).fill() } else { NSRect(x: 0, y: f.minY - 0.5, width: bounds.width, height: 1).fill() }
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        storage.addLayoutManager(layoutManager)
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func build(_ key: ScriptPager.LayoutKey) {
        rebuildWork?.cancel()
        pendingKey = nil
        layoutKey = key
        pageSize = CGSize(width: max(100, key.size.width), height: max(100, key.size.height))
        let inner = CGSize(width: pageSize.width - inset * 2, height: pageSize.height - inset * 2)
        // きっかけの帯の分を空ける（縦書きは下、横書きは右）
        bandThickness = key.vertical ? min(170, max(90, pageSize.height * 0.3)) : min(260, max(150, pageSize.width * 0.38))
        // 1 行の長さに「人物名欄 ＋ 本文」の字数が入る大きさにする（PDF の書き出しと同じ）
        let lineChars = Double(key.script.characterLength + key.script.bodyLength)
        let lineLength = Double((key.vertical ? inner.height : inner.width) - bandThickness)
        // 文字間を空けると 1 字の長さが (1 ＋ 文字間) 倍になる
        let perChar = 1 + key.charSpacing
        fontSize = max(6, min(key.fontSize, (lineLength / (lineChars * perChar + 0.3) * 2).rounded(.down) / 2))
        let lineEnd = CGFloat(lineChars * perChar * fontSize + fontSize * 0.3)

        storage.setAttributedString(makeText(key.script, fontSize: fontSize, lineSpacing: key.lineSpacing, charSpacing: key.charSpacing))
        for tv in textViews { tv.removeFromSuperview() }
        for b in bands { b.removeFromSuperview() }
        textViews = []
        bands = []
        attached = []
        pageRanges = []
        while !layoutManager.textContainers.isEmpty { layoutManager.removeTextContainer(at: 0) }
        stopAnimation()
        justBuilt = true
        lanesDirty = true
        reportedPage = -1
        lastSelected = nil
        selectedRanges = []

        // 文章が全部収まるまでページ（入れ物）を足す
        var pages: [[String]] = []
        repeat {
            let container = NSTextContainer(size: pageSize)
            container.widthTracksTextView = false
            container.heightTracksTextView = false
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            let tv = ScriptTextView(frame: NSRect(origin: .zero, size: pageSize), textContainer: container)
            tv.isEditable = false
            tv.isSelectable = false
            tv.drawsBackground = false
            tv.textContainerInset = NSSize(width: inset, height: inset)
            tv.minSize = pageSize
            tv.maxSize = pageSize
            tv.isVerticallyResizable = false
            tv.isHorizontallyResizable = false
            if key.vertical { tv.setLayoutOrientation(.vertical) }
            // 入れ物の大きさは「行の長さ × 行を並べる幅」
            container.size = key.vertical ? CGSize(width: lineEnd, height: inner.width) : CGSize(width: lineEnd, height: inner.height)
            // 縦書きにすると表示の枠の縦横も入れ替わるので、ページの大きさに戻す
            tv.frame = NSRect(origin: .zero, size: pageSize)
            tv.anchorAt = { [weak self] index in self?.anchor(at: index) }
            textViews.append(tv)
            bands.append(CueBandView())
            layoutManager.ensureLayout(for: container)
            let range = layoutManager.characterRange(forGlyphRange: layoutManager.glyphRange(for: container), actualGlyphRange: nil)
            pageRanges.append(range)
            // このページにある行（台本の順）
            pages.append(lineRanges.filter { NSIntersectionRange($0.value, range).length > 0 }
                .sorted { $0.value.location < $1.value.location }.map(\.key))
            if range.length == 0 || NSMaxRange(range) >= storage.length || textViews.count > 3000 { break }
        } while true
        // 画面を描いている最中に状態を変えないよう、次の回にまわす
        DispatchQueue.main.async { MainActor.assumeIsolated { ScriptPageIndex.shared.pages = pages } }
    }

    /// page のページを出す。いま見えているページと違えば、そこまで流す（組み直した直後は飛ぶ）
    func show(page: Int, marks: [CueMark], notes: [ScriptNote], active: Set<UUID>) {
        guard textViews.indices.contains(page) else { return }
        let marksChanged = marks != lastMarks || active != lastActive || notes != lastNotes
        if marks != lastMarks { lanesDirty = true }
        lastMarks = marks
        lastNotes = notes
        lastActive = active
        let target = CGFloat(page) * pageLength
        if justBuilt {
            justBuilt = false
            offset = min(target, maxOffset)
            reportedPage = page
        } else if let t = animTarget {
            if abs(t - target) > 0.5 { animate(to: target) }
        } else if page != currentPage {
            reportedPage = page
            animate(to: target)
        }
        layoutPages(refreshAll: marksChanged || attached.isEmpty)
    }

    /// 見えているページ（と帯）を並べる。新しく見えたページの帯は、文字の位置が決まってから描く
    private func layoutPages(refreshAll: Bool) {
        guard !textViews.isEmpty else { return }
        let len = pageLength
        let first = max(0, Int((offset / len).rounded(.down)))
        let last = min(textViews.count - 1, Int((offset / len).rounded(.up)))
        let visible = Set(first...max(first, last))
        var added = Set<Int>()
        for i in visible.sorted() {
            let tv = textViews[i], band = bands[i]
            // 縦書きは先のページが左（offset が増えると右へ動いて出てくる）、横書きは下
            let frame = vertical
                ? NSRect(x: offset - CGFloat(i) * len, y: 0, width: pageSize.width, height: pageSize.height)
                : NSRect(x: 0, y: CGFloat(i) * len - offset, width: pageSize.width, height: pageSize.height)
            tv.frame = frame
            band.frame = vertical
                ? NSRect(x: frame.minX, y: frame.maxY - bandThickness, width: pageSize.width, height: bandThickness)
                : NSRect(x: frame.maxX - bandThickness, y: frame.minY, width: bandThickness, height: pageSize.height)
            if !attached.contains(i) {
                addSubview(tv)
                addSubview(band)
                added.insert(i)
            }
        }
        for i in attached.subtracting(visible) {
            textViews[i].removeFromSuperview()
            bands[i].removeFromSuperview()
        }
        attached = visible
        needsDisplay = true
        let refresh = refreshAll ? visible : added
        guard !refresh.isEmpty else { return }
        // 帯の位置は、文字の画面上の位置から決めるので、表示が済んでから
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for i in refresh where self.attached.contains(i) { self.updateBand(page: i) }
        }
    }

    // MARK: きっかけの帯

    /// そのページのきっかけを、帯に描く形にする
    private func updateBand(page: Int) {
        guard textViews.indices.contains(page), window != nil else { return }
        let tv = textViews[page]
        let band = bands[page]
        let range = pageRanges[page]
        // 文字の位置は、画面に見えている文字でないと取れない。スクロールの途中で半分しか見えていないページも
        // 測れるよう、測る間だけページをパネルにぴったり重ねる（すぐ戻すので画面には出ない）
        let savedFrame = tv.frame
        tv.frame = NSRect(origin: .zero, size: pageSize)
        defer { tv.frame = savedFrame }
        let vertical = self.vertical
        // 線の向きの位置: 縦書きは x（右から左へ進む）、横書きは y（上から下へ進む）。ページ（帯）の中の座標で
        // ページをまたぐ線は、ページの端まで引く（となりのページの線とつながる）
        let startEdge = vertical ? pageSize.width : 0
        let endEdge = vertical ? 0 : pageSize.height
        if lanesDirty { computeLanes() }
        let fs = CGFloat(fontSize)
        /// ずらす量（台本の進む向きが＋。縦書きは左へ、横書きは下へ）
        func shift(_ a: CueAnchor?) -> CGFloat {
            let n = CGFloat(a?.nudge ?? 0) * fs
            return vertical ? -n : n
        }
        func pos(_ index: Int) -> CGFloat? {
            guard NSLocationInRange(index, range) else { return nil }
            var screen = tv.firstRect(forCharacterRange: NSRange(location: index, length: 1), actualRange: nil)
            guard let win = window, screen.width > 0 || screen.height > 0 else { return nil }
            screen = win.convertFromScreen(screen)
            // ページの中の座標に（縦書きの文字の表示は座標が回っているので、パネルで測る。ページはいまパネルの左上にある。
            // 帯はページと同じ x〈縦書き〉・y〈横書き〉から始まるので、そのまま帯の座標になる）
            let r = convert(screen, from: nil)
            return vertical ? r.midX : r.midY
        }
        var items: [CueBandView.Item] = []
        for m in lastMarks {
            guard let s = location(of: m.start) else { continue }
            let e = m.end.flatMap { location(of: $0) }
            let lit = lastActive.contains(m.id)
            if let e {
                let (a, b) = s <= e ? (s, e) : (e, s)
                // このページにかかっていなければ描かない
                guard a < NSMaxRange(range), b >= range.location else { continue }
                // 始まりと終わりが入れ替わっていれば、ずらす量も入れ替える
                let (na, nb) = s <= e ? (m.start, m.end) : (m.end, m.start)
                let from = pos(a).map { $0 + shift(na) } ?? startEdge
                let to = pos(b).map { $0 + shift(nb) } ?? endEdge
                items.append(.init(mark: m, start: from, end: to, startsHere: pos(a) != nil, endsHere: pos(b) != nil, lit: lit,
                                   swapped: s > e, lane: laneOf[m.id] ?? 0))
            } else if let p = pos(s) {
                items.append(.init(mark: m, start: p + shift(m.start), end: nil, startsHere: true, endsHere: false, lit: lit,
                                   lane: laneOf[m.id] ?? 0))
            }
        }
        var notes: [(note: ScriptNote, pos: CGFloat)] = []
        for n in lastNotes {
            if let l = location(of: n.anchor), let p = pos(l) { notes.append((n, p + shift(n.anchor))) }
        }
        band.notes = notes
        band.anchorAt = { [weak self] value in self?.anchorAt(page: page, value) }
        band.fontSize = fs
        band.vertical = vertical
        band.items = items
        band.needsDisplay = true
    }

    /// 帯の段を、台本全体を通して決める。台本の頭から順に、線とラベルが占める範囲（文字の位置で数える）が
    /// 重ならないように段を割り振る。ページごとに決めると、ページをまたぐ線の段が変わってずれるため
    private func computeLanes() {
        lanesDirty = false
        laneOf = [:]
        guard !textViews.isEmpty, storage.length > 0 else { return }
        // 1 ポイントあたりの文字数（ページの文字数 ÷ 行を並べる長さ。おおよそ）
        let along = max(1, (vertical ? pageSize.width : pageSize.height) - inset * 2)
        let perPoint = Double(storage.length) / Double(CGFloat(textViews.count) * along)
        let nameFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let keyFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        let lanes = vertical ? max(1, Int((bandThickness - 6) / 50)) : 4
        var spans: [(id: UUID, lo: Double, hi: Double)] = []
        for m in lastMarks {
            guard let s = location(of: m.start) else { continue }
            let e = m.end.flatMap { location(of: $0) }
            let lo = Double(min(s, e ?? s))
            var hi = Double(max(s, e ?? s))
            if vertical {
                // ラベル（札と名前）は始まりから先へ、終わりの F.O. は線の先へ伸びる
                let label = (m.label as NSString).size(withAttributes: [.font: keyFont]).width
                    + (m.name as NSString).size(withAttributes: [.font: nameFont]).width + 24
                hi = max(hi, lo + Double(label) * perPoint)
                if e != nil { hi += 44 * perPoint }
            } else {
                hi = max(hi, lo + 20 * perPoint)
            }
            spans.append((m.id, lo, hi))
        }
        var laneEnd = [Double](repeating: -.greatestFiniteMagnitude, count: lanes)
        let gap = 6 * perPoint
        for sp in spans.sorted(by: { $0.lo < $1.lo }) {
            let lane = laneEnd.firstIndex { $0 + gap <= sp.lo } ?? (laneEnd.indices.min { laneEnd[$0] < laneEnd[$1] } ?? 0)
            laneEnd[lane] = max(laneEnd[lane], sp.hi)
            laneOf[sp.id] = lane
        }
    }

    /// 帯の中の位置（縦書きは x、横書きは y） → きっかけの位置。いちばん近い行の頭の文字に結びつけ、
    /// クリックした位置とのずれを nudge にする（行間などにも、クリックしたところに線が始まる）
    private func anchorAt(page: Int, _ value: CGFloat) -> CueAnchor? {
        guard textViews.indices.contains(page), let win = window else { return nil }
        let tv = textViews[page]
        let range = pageRanges[page]
        guard range.length > 0 else { return nil }
        let saved = tv.frame
        tv.frame = NSRect(origin: .zero, size: pageSize)
        defer { tv.frame = saved }
        let fs = CGFloat(fontSize)
        func charPos(_ index: Int) -> CGFloat? {
            var screen = tv.firstRect(forCharacterRange: NSRange(location: index, length: 1), actualRange: nil)
            guard screen.width > 0 || screen.height > 0 else { return nil }
            screen = win.convertFromScreen(screen)
            let r = convert(screen, from: nil)
            return vertical ? r.midX : r.midY
        }
        // 行の頭のほうから順に、台本の行（場面の見出しでないもの）が見つかるまで探す
        var found: CueAnchor?
        for k in 0..<12 {
            let along = inset + fs * (0.5 + CGFloat(k) * 2)
            let pt = vertical ? NSPoint(x: value, y: along) : NSPoint(x: along, y: value)
            var idx = tv.characterIndexForInsertion(at: tv.convert(pt, from: self))
            idx = min(max(idx, range.location), NSMaxRange(range) - 1)
            if let a = anchor(at: idx) { found = a; break }
        }
        guard var a = found, let loc = location(of: a), let p = charPos(loc) else { return found }
        let diff = value - p
        let n = Double((vertical ? -diff : diff) / max(fs, 1))
        a.nudge = abs(n) < 0.05 ? nil : (n * 100).rounded() / 100
        return a
    }

    /// 文章の位置 → きっかけの位置（行と、本文の何文字目か）。本文より前（人物名など）なら行の頭
    private func anchor(at index: Int) -> CueAnchor? {
        guard storage.length > 0 else { return nil }
        let i = min(max(index, 0), storage.length - 1)
        guard let uid = storage.attribute(.scriptLine, at: i, effectiveRange: nil) as? String else { return nil }
        var r = NSRange()
        if let piece = storage.attribute(.scriptPiece, at: i, effectiveRange: &r) as? TextPiece {
            return CueAnchor(line: uid, offset: piece.base + (i - r.location))
        }
        // 本文の直後（行の終わり）なら、本文の終わり
        if i > 0, let piece = storage.attribute(.scriptPiece, at: i - 1, effectiveRange: &r) as? TextPiece, piece.line == uid {
            return CueAnchor(line: uid, offset: piece.base + r.length)
        }
        return CueAnchor(line: uid, offset: 0)
    }

    /// きっかけの位置 → 文章の位置
    private func location(of a: CueAnchor) -> Int? {
        guard let start = textStarts[a.line], let range = lineRanges[a.line] else { return nil }
        return min(start + max(0, a.offset), NSMaxRange(range) - 1)
    }

    /// 選んだ位置に色を付ける（文字数は変えないので、ページは変わらない）
    func applyHighlight(selected: CueAnchor?) {
        guard selected != lastSelected else { return }
        storage.beginEditing()
        for r in selectedRanges { storage.removeAttribute(.backgroundColor, range: r) }
        selectedRanges = []
        if let s = selected, let lineRange = lineRanges[s.line] {
            // 行をうすく、選んだ文字を濃く
            storage.addAttribute(.backgroundColor, value: NSColor.controlAccentColor.withAlphaComponent(0.12), range: lineRange)
            selectedRanges.append(lineRange)
            if let loc = location(of: s), loc < storage.length {
                let r = NSRange(location: loc, length: 1)
                storage.addAttribute(.backgroundColor, value: NSColor.controlAccentColor.withAlphaComponent(0.55), range: r)
                selectedRanges.append(r)
            }
        }
        storage.endEditing()
        lastSelected = selected
        for i in attached { textViews[i].needsDisplay = true }
    }

    // MARK: 文章を作る

    /// 半角の英数・記号・空白を全角にする（字の幅をそろえて、紙の台本と同じ位置で折り返す。ScenarioWriterSolo と同じ）
    static func fullWidth(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.map { u -> Unicode.Scalar in
            if u.value == 0x20 { return "\u{3000}" }
            if (0x21...0x7E).contains(u.value) { return Unicode.Scalar(u.value + 0xFEE0) ?? u }
            return u
        }))
    }

    private func makeText(_ script: ScriptDocument, fontSize: Double, lineSpacing: Double, charSpacing: Double) -> NSAttributedString {
        let out = NSMutableAttributedString()
        lineRanges = [:]
        textStarts = [:]
        let fs = CGFloat(fontSize)
        let nameW = script.characterLength
        let bodyW = script.bodyLength
        let body = NSFont(name: "HiraMinProN-W3", size: fs) ?? .systemFont(ofSize: fs)
        let bold = NSFont(name: "HiraMinProN-W6", size: fs) ?? .boldSystemFont(ofSize: fs)
        let sceneFont = NSFont(name: "HiraKakuProN-W6", size: fs * 1.1) ?? .boldSystemFont(ofSize: fs * 1.1)

        for scene in script.scenes where scene.valid {
            let p = NSMutableParagraphStyle()
            p.firstLineHeadIndent = fs * 2
            p.headIndent = fs * 2
            p.paragraphSpacingBefore = fs * 0.8
            p.paragraphSpacing = fs * 0.4
            out.append(NSAttributedString(string: Self.fullWidth(scene.name.trimmingCharacters(in: .whitespaces)) + "\n",
                                          attributes: [.font: sceneFont, .foregroundColor: NSColor.textColor, .paragraphStyle: p]))
            for line in scene.lines {
                let start = out.length
                let style = script.style(line.type)
                let mode = style?.mode ?? 0
                let bodyIndent = min(max(style?.indent ?? 0, 0), bodyW - 2)
                // 名前欄 ＋ 本文の字下げぶんだけ、2 行目からも下げる（PDF の書き出しと同じ）
                let para = NSMutableParagraphStyle()
                para.firstLineHeadIndent = 0
                para.headIndent = CGFloat(nameW + bodyIndent) * fs * CGFloat(1 + charSpacing)
                para.lineSpacing = fs * CGFloat(lineSpacing)
                para.paragraphSpacing = fs * 0.25
                // 黒はダークモードでも読めるよう、文字の標準の色にする
                let hex = (style?.color ?? "#000000").lowercased()
                let color = hex == "#000000" ? NSColor.textColor : (NSColor(hex: hex) ?? .textColor)
                // 文字間は人物名欄にも同じだけ付ける（名前欄と本文の字の位置がそろうように）
                let attrs: [NSAttributedString.Key: Any] = [.font: body, .foregroundColor: color, .paragraphStyle: para, .scriptLine: line.uid,
                                                            .kern: fs * CGFloat(charSpacing)]

                // 名前欄（人物名、または省略文字を右寄せ）。字数は人物名欄の文字数にそろえる
                let showsName = mode == 1 || mode == 2
                let name = showsName ? Self.fullWidth(script.characterName(line.character) ?? "") : ""
                let abbr = Self.fullWidth(style?.abbr ?? "")
                var head: String
                if name.isEmpty {
                    head = String(repeating: "\u{3000}", count: max(0, nameW - abbr.count)) + abbr
                } else {
                    head = abbr.isEmpty ? name : name + "\u{3000}" + abbr
                    head += String(repeating: "\u{3000}", count: max(0, nameW - head.count))
                }
                var headAttrs = attrs
                if !name.isEmpty { headAttrs[.font] = bold }
                out.append(NSAttributedString(string: head + String(repeating: "\u{3000}", count: bodyIndent), attributes: headAttrs))

                // 本文（「」で囲むときは前後に足す）
                let quoted = (mode == 1 && script.kagikakko) || mode == 3
                if quoted { out.append(NSAttributedString(string: "「", attributes: attrs)) }
                textStarts[line.uid] = out.length
                var a = attrs
                a[.scriptPiece] = TextPiece(line: line.uid, base: 0)
                out.append(NSAttributedString(string: Self.fullWidth(line.text).replacingOccurrences(of: "\n", with: "\u{3000}"), attributes: a))
                if quoted { out.append(NSAttributedString(string: "」", attributes: attrs)) }
                out.append(NSAttributedString(string: "\n", attributes: attrs))
                lineRanges[line.uid] = NSRange(location: start, length: out.length - start)
            }
        }
        return out
    }
}

/// きっかけの帯。きっかけの位置から色付きの線を引き、押すキー・名前・メモを横書きで添える（音響台本の書き方）。
/// 縦書きのときはページの下（線は横、右から左へ）、横書きのときはページの右（線は縦、上から下へ）
final class CueBandView: NSView {
    struct Item {
        var mark: CueMark
        /// 線の始まり・終わり（帯の外側のページの座標で、縦書きは x、横書きは y）。終わりが nil なら線を引かない（効果音など）
        var start: CGFloat
        var end: CGFloat?
        /// このページで始まる・終わるか（始まりの印とラベル、終わりの F.O. を描くか）
        var startsHere: Bool
        var endsHere: Bool
        var lit: Bool
        /// 止める位置が始まりより前（線の始まりが「終わり」の位置）
        var swapped = false
        /// 帯の何段目に描くか（台本全体で決めるので、ページをまたいでも同じ段）
        var lane = 0
    }

    var vertical = true
    var items: [Item] = []
    /// 文字の大きさ（印をドラッグしてずらした量を、文字の大きさに対する割合にする）
    var fontSize: CGFloat = 16
    /// 帯に書いたメモと、その位置
    var notes: [(note: ScriptNote, pos: CGFloat)] = []
    /// 帯の中の位置 → 台本のきっかけの位置（右クリックで「ここのきっかけにする」）
    var anchorAt: ((CGFloat) -> CueAnchor?)?
    private var noteHits: [(rect: NSRect, id: UUID)] = []
    /// 始まり・終わりの印の場所（ドラッグで線の位置をずらす）
    private var ticks: [(rect: NSRect, item: Int, isEnd: Bool)] = []
    /// ドラッグ中の印
    private var dragging: (item: Int, isEnd: Bool, origin: CGFloat, base: CGFloat)?
    /// 描いたラベルと線の場所（⌘／control＋クリックで鳴らすため）
    private var hits: [(rect: NSRect, id: UUID)] = []

    override var isFlipped: Bool { true }

    /// ⌘＋クリック・control＋クリックで、その印のキー・曲を鳴らす
    override func mouseDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) || flags.contains(.control) else { return dragTick(event) }
        let p = convert(event.locationInWindow, from: nil)
        // 重なっていたら、あとに描いた（上に見えている）ものを
        guard let hit = hits.last(where: { $0.rect.insetBy(dx: -3, dy: -3).contains(p) }) else { return }
        MainActor.assumeIsolated { ProModel.shared.play(markID: hit.id) }
    }

    /// 帯に書いたメモ。縦書きは帯のいちばん下の段に、位置の印から左へ。横書きは帯の右に、位置の高さで
    private func drawNotes() {
        let attrs: [NSAttributedString.Key: Any] = [.font: memoFont, .foregroundColor: NSColor.systemOrange]
        for (note, p) in notes {
            let t = note.text as NSString
            let size = t.size(withAttributes: attrs)
            NSColor.systemOrange.setFill()
            let rect: NSRect
            if vertical {
                let y = bounds.height - size.height - 6
                NSRect(x: p - 0.75, y: y - 4, width: 1.5, height: size.height + 4).fill()
                rect = NSRect(x: p - size.width - 4, y: y, width: size.width, height: size.height)
            } else {
                let x = bounds.width - size.width - 8
                NSRect(x: x - 6, y: p - 0.75, width: 4, height: 1.5).fill()
                rect = NSRect(x: x, y: p - size.height / 2, width: size.width, height: size.height)
            }
            t.draw(at: rect.origin, withAttributes: attrs)
            noteHits.append((rect.insetBy(dx: -4, dy: -3), note.id))
        }
    }

    /// 右クリック。何もないところ: 選んでいるキー・曲を「ここのきっかけにする」「ここで止める」、メモを書く。
    /// 印・線: 鳴らす・メモ・線の位置を戻す・止める位置を外す・結びつきを外す。書いたメモ: 直す・消す。
    /// （control＋クリックは mouseDown で「鳴らす」にしているので、ここに来るのは右クリックだけ）
    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        let value = vertical ? p.x : p.y
        return MainActor.assumeIsolated { () -> NSMenu? in
            let pro = ProModel.shared
            let locked = AppModel.shared.showMode
            let menu = NSMenu()
            // 書いたメモ
            if let hit = noteHits.last(where: { $0.rect.contains(p) }),
               let note = notes.first(where: { $0.note.id == hit.id })?.note {
                if locked {
                    menu.addItem(NSMenuItem(title: L("本番モード中は書き込みを変えられません"), action: nil, keyEquivalent: ""))
                    return menu
                }
                menu.addItem(ClosureMenuItem(title: L("メモを直す…")) {
                    if let t = pro.askText(title: L("メモ"), initial: note.text) { pro.setNote(note.id, t) }
                })
                menu.addItem(ClosureMenuItem(title: L("メモを消す")) { pro.setNote(note.id, "") })
                return menu
            }
            // きっかけの印・線
            if let hit = hits.last(where: { $0.rect.insetBy(dx: -3, dy: -3).contains(p) }),
               let item = items.first(where: { $0.mark.id == hit.id }) {
                let m = item.mark
                let id = m.id
                menu.addItem(ClosureMenuItem(title: L("「%@」（%@）を鳴らす", m.name, m.label)) { pro.play(markID: id) })
                if pro.isPlaying(markID: id) {
                    menu.addItem(ClosureMenuItem(title: L("「%@」（%@）を止める（フェードアウト）", m.name, m.label)) { pro.stop(markID: id) })
                }
                menu.addItem(.separator())
                if locked {
                    menu.addItem(NSMenuItem(title: L("本番モード中は結びつけを変えられません"), action: nil, keyEquivalent: ""))
                    return menu
                }
                menu.addItem(ClosureMenuItem(title: m.memo.isEmpty ? L("メモを書く…") : L("メモを直す…")) {
                    if let t = pro.askText(title: L("「%@」（%@）のメモ", m.name, m.label), initial: m.memo) { pro.setMemo(id, t) }
                })
                if let a = anchorAt?(value) {
                    menu.addItem(ClosureMenuItem(title: L("ここで止める（線の終わり）")) { pro.setEnd(id, at: a) })
                }
                if m.start.nudge != nil || m.end?.nudge != nil {
                    menu.addItem(ClosureMenuItem(title: L("線の位置を文字に戻す")) {
                        pro.setNudge(id, isEnd: false, nil)
                        pro.setNudge(id, isEnd: true, nil)
                    })
                }
                if m.end != nil {
                    menu.addItem(ClosureMenuItem(title: L("止める位置を外す（線を消して、始まりの印だけにする）")) { pro.setEnd(id, at: nil) })
                }
                menu.addItem(.separator())
                menu.addItem(ClosureMenuItem(title: L("「%@」（%@）の結びつきを外す（台本から消す）", m.name, m.label)) { pro.unlink(id) })
                return menu
            }
            // 何もないところ
            if locked {
                menu.addItem(NSMenuItem(title: L("本番モード中は書き込みを変えられません"), action: nil, keyEquivalent: ""))
                return menu
            }
            guard let a = anchorAt?(value) else { return nil }
            if let cue = pro.selectedCue {
                menu.addItem(ClosureMenuItem(title: L("「%@」（%@）を、ここのきっかけにする", cue.name, cue.label)) {
                    pro.link(cue.id, to: a)
                })
                if pro.anchor(for: cue.id) != nil {
                    menu.addItem(ClosureMenuItem(title: L("「%@」（%@）を、ここで止める（線の終わり）", cue.name, cue.label)) {
                        pro.setEnd(cue.id, at: a)
                    })
                }
            } else {
                menu.addItem(NSMenuItem(title: L("先にキーかリストの曲を選ぶと、ここに結びつけられます"), action: nil, keyEquivalent: ""))
            }
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(title: L("ここにメモを書く…")) {
                if let t = pro.askText(title: L("メモ"), initial: "") { pro.addNote(at: a, t) }
            })
            return menu
        }
    }

    /// 始まり・終わりの縦の印（横書きは横の印）をドラッグして、線の位置をずらす。ダブルクリックで文字の位置に戻す
    private func dragTick(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard !AppModel.shared.showMode,
              let t = ticks.last(where: { $0.rect.contains(p) }), items.indices.contains(t.item) else { return }
        let item = items[t.item]
        // 印が表しているのは、ふだんは 始まり＝start・終わり＝end。入れ替わっていれば逆
        let isEnd = item.swapped ? !t.isEnd : t.isEnd
        let anchor = isEnd ? item.mark.end : item.mark.start
        let id = item.mark.id
        if event.clickCount >= 2 {
            MainActor.assumeIsolated { ProModel.shared.setNudge(id, isEnd: isEnd, nil) }
            return
        }
        let current = t.isEnd ? (item.end ?? item.start) : item.start
        // ずらす前の位置（文字の位置）
        let n = CGFloat(anchor?.nudge ?? 0) * fontSize
        let base = current - (vertical ? -n : n)
        dragging = (t.item, t.isEnd, vertical ? p.x : p.y, current)
        var moved = false
        // 離すまで、ここでマウスを追う
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let q = convert(next.locationInWindow, from: nil)
            let d = (vertical ? q.x : q.y) - (dragging?.origin ?? 0)
            let now = current + d
            if t.isEnd { items[t.item].end = now } else { items[t.item].start = now }
            moved = moved || abs(d) > 1
            needsDisplay = true
            displayIfNeeded()
            if next.type == .leftMouseUp { break }
        }
        dragging = nil
        guard moved else { return }
        let final = t.isEnd ? (items[t.item].end ?? items[t.item].start) : items[t.item].start
        let shifted = final - base
        let nudge = Double((vertical ? -shifted : shifted) / max(fontSize, 1))
        MainActor.assumeIsolated { ProModel.shared.setNudge(id, isEnd: isEnd, nudge) }
    }

    override func resetCursorRects() {
        for t in ticks { addCursorRect(t.rect, cursor: vertical ? .resizeLeftRight : .resizeUpDown) }
    }

    private let keyFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
    private let nameFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    private let memoFont = NSFont.systemFont(ofSize: 11)
    private let endFont = NSFont.systemFont(ofSize: 12, weight: .bold)

    override func draw(_ dirtyRect: NSRect) {
        hits = []
        ticks = []
        noteHits = []
        defer { window?.invalidateCursorRects(for: self) }
        // 台本との境の線
        NSColor.separatorColor.setFill()
        if vertical { NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill() } else { NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill() }
        if vertical { drawVertical() } else { drawHorizontal() }
        drawNotes()
    }

    /// ラベル（札と名前）とメモの大きさ
    private func labelSize(_ m: CueMark, continued: Bool) -> (key: NSSize, name: NSSize, memo: NSSize, total: NSSize) {
        let key = (m.label as NSString).size(withAttributes: [.font: keyFont])
        let nameText = (continued ? "… " : "") + m.name
        let name = (nameText as NSString).size(withAttributes: [.font: nameFont])
        let memo = m.memo.isEmpty ? .zero : (m.memo as NSString).size(withAttributes: [.font: memoFont])
        let first = key.width + 10 + 5 + name.width
        return (key, name, memo, NSSize(width: max(first, memo.width), height: 18 + (m.memo.isEmpty ? 0 : memo.height + 1)))
    }

    /// 札（キーの文字）と名前を描く。origin はラベルの左上
    private func drawLabel(_ item: Item, at origin: NSPoint) {
        let m = item.mark
        let s = labelSize(m, continued: !item.startsHere)
        let keyRect = NSRect(x: origin.x, y: origin.y, width: s.key.width + 10, height: 17)
        hits.append((NSRect(origin: origin, size: s.total), m.id))
        let shape = NSBezierPath(roundedRect: keyRect, xRadius: 4, yRadius: 4)
        m.color.withAlphaComponent(item.lit ? 1 : 0.75).setFill()
        shape.fill()
        if item.lit {
            NSColor.labelColor.setStroke()
            shape.lineWidth = 1.5
            shape.stroke()
        }
        (m.label as NSString).draw(at: NSPoint(x: keyRect.minX + 5, y: keyRect.minY + (17 - s.key.height) / 2),
                                   withAttributes: [.font: keyFont, .foregroundColor: NSColor.white])
        let nameText = (item.startsHere ? "" : "… ") + m.name
        (nameText as NSString).draw(at: NSPoint(x: keyRect.maxX + 5, y: origin.y + (17 - s.name.height) / 2),
                                    withAttributes: [.font: nameFont, .foregroundColor: NSColor.labelColor])
        if !m.memo.isEmpty {
            (m.memo as NSString).draw(at: NSPoint(x: keyRect.maxX + 5, y: origin.y + 18),
                                      withAttributes: [.font: memoFont, .foregroundColor: NSColor.secondaryLabelColor])
        }
    }

    // 縦書き: 線は横。始まり（右）に縦の印、ラベルは線の下に、始まりの印に右をそろえる
    private func drawVertical() {
        let laneHeight: CGFloat = 50
        let lanes = max(1, Int((bounds.height - 6) / laneHeight))
        // 始まりが右（ページの先）のものから順に段を決める
        for (index, item) in items.enumerated().sorted(by: { $0.element.start > $1.element.start }) {
            let s = labelSize(item.mark, continued: !item.startsHere)
            let right = item.start
            // 段は台本全体で決めてある（ページをまたいでも同じ段）
            let lane = min(item.lane, lanes - 1)
            let top = 6 + CGFloat(lane) * laneHeight
            let color = item.mark.color.withAlphaComponent(item.lit ? 1 : 0.7)
            color.setFill()
            let thick: CGFloat = item.lit ? 8 : 5
            hits.append((NSRect(x: min(item.end ?? right - 14, right), y: top, width: max(14, abs(right - (item.end ?? right - 14))), height: thick + 8), item.mark.id))
            if let end = item.end {
                NSRect(x: min(end, right), y: top + 4, width: abs(right - end), height: thick).fill()
                if item.endsHere {
                    NSRect(x: end - 1.5, y: top, width: 3, height: thick + 8).fill()
                    ticks.append((NSRect(x: end - 5, y: top - 3, width: 10, height: thick + 14), index, true))
                    let t = item.mark.endLabel as NSString
                    let ts = t.size(withAttributes: [.font: endFont])
                    // 終わりの印は線の延長（左）に、線と同じ高さで（下のラベルと重ならないように）
                    t.draw(at: NSPoint(x: end - ts.width - 5, y: top + 4 + thick / 2 - ts.height / 2),
                           withAttributes: [.font: endFont, .foregroundColor: NSColor.systemRed])
                }
            } else {
                // 効果音など: 始まりから短い線
                NSRect(x: right - 14, y: top + 4, width: 14, height: thick).fill()
            }
            if item.startsHere {
                NSRect(x: right - 1.5, y: top, width: 3, height: thick + 8).fill()
                ticks.append((NSRect(x: right - 5, y: top - 3, width: 10, height: thick + 14), index, false))
            }
            drawLabel(item, at: NSPoint(x: right - s.total.width, y: top + thick + 8))
        }
    }

    // 横書き: 線は縦（上から下）。線は左の細い段に並べ、ラベルは右に、始まりの高さにそろえて並べる
    private func drawHorizontal() {
        let slotWidth: CGFloat = 14
        let slots = 4
        var labelBottom: CGFloat = 0
        let labelX = 10 + slotWidth * CGFloat(slots) + 6
        for (index, item) in items.enumerated().sorted(by: { $0.element.start < $1.element.start }) {
            let s = labelSize(item.mark, continued: !item.startsHere)
            let top = item.start
            let bottom = item.end ?? top + 14
            let slot = min(item.lane, slots - 1)
            let x = 10 + slotWidth * CGFloat(slot)
            let color = item.mark.color.withAlphaComponent(item.lit ? 1 : 0.7)
            color.setFill()
            let thick: CGFloat = item.lit ? 7 : 4
            NSRect(x: x, y: min(top, bottom), width: thick, height: abs(bottom - top)).fill()
            hits.append((NSRect(x: x - 4, y: min(top, bottom), width: thick + 8, height: abs(bottom - top)), item.mark.id))
            if item.startsHere {
                NSRect(x: x - 4, y: top - 1.5, width: thick + 8, height: 3).fill()
                ticks.append((NSRect(x: x - 6, y: top - 5, width: thick + 12, height: 10), index, false))
            }
            if item.end != nil, item.endsHere {
                NSRect(x: x - 4, y: bottom - 1.5, width: thick + 8, height: 3).fill()
                ticks.append((NSRect(x: x - 6, y: bottom - 5, width: thick + 12, height: 10), index, true))
                (item.mark.endLabel as NSString).draw(at: NSPoint(x: labelX, y: bottom - 8),
                                                      withAttributes: [.font: endFont, .foregroundColor: NSColor.systemRed])
            }
            // ラベルは始まりの高さに。前のラベルと重なるなら下へずらし、細い線で結ぶ
            let y = max(top - 9, labelBottom + 2)
            if abs(y - (top - 9)) > 1 {
                color.setStroke()
                let path = NSBezierPath()
                path.move(to: NSPoint(x: x + thick, y: top))
                path.line(to: NSPoint(x: labelX - 2, y: y + 9))
                path.lineWidth = 1
                path.stroke()
            }
            drawLabel(item, at: NSPoint(x: labelX, y: y))
            labelBottom = y + s.total.height
        }
    }
}

/// 台本の 1 ページ。クリックで位置を選び、右クリックでキューを結びつける・止める位置を決める
final class ScriptTextView: NSTextView {
    var anchorAt: ((Int) -> CueAnchor?)?

    private func anchor(_ event: NSEvent) -> CueAnchor? {
        let p = convert(event.locationInWindow, from: nil)
        return anchorAt?(characterIndexForInsertion(at: p))
    }

    override func mouseDown(with event: NSEvent) {
        AppModel.endEditing()
        let a = anchor(event)
        MainActor.assumeIsolated { ProModel.shared.selected = a }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let a = anchor(event) else { return nil }
        return MainActor.assumeIsolated { () -> NSMenu? in
            let pro = ProModel.shared
            pro.selected = a
            let menu = NSMenu()
            if AppModel.shared.showMode {
                menu.addItem(NSMenuItem(title: L("本番モード中は結びつけを変えられません"), action: nil, keyEquivalent: ""))
                return menu
            }
            if let cue = pro.selectedCue {
                menu.addItem(ClosureMenuItem(title: L("「%@」（%@）を、ここのきっかけにする", cue.name, cue.label)) {
                    pro.link(cue.id, to: a)
                })
                if pro.anchor(for: cue.id) != nil {
                    menu.addItem(ClosureMenuItem(title: L("「%@」（%@）を、ここで止める（線の終わり）", cue.name, cue.label)) {
                        pro.setEnd(cue.id, at: a)
                    })
                    if pro.end(for: cue.id) != nil {
                        menu.addItem(ClosureMenuItem(title: L("「%@」（%@）の止める位置を外す", cue.name, cue.label)) {
                            pro.setEnd(cue.id, at: nil)
                        })
                    }
                }
            } else {
                menu.addItem(NSMenuItem(title: L("先にキーかリストの曲を選ぶと、ここに結びつけられます"), action: nil, keyEquivalent: ""))
            }
            let linked = pro.marks(for: a.line)
            if !linked.isEmpty {
                menu.addItem(.separator())
                for m in linked {
                    menu.addItem(ClosureMenuItem(title: L("「%@」（%@）の結びつきを外す", m.name, m.label)) { pro.unlink(m.id) })
                }
            }
            return menu
        }
    }
}

/// 押したときに処理を呼ぶメニュー項目
final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { MainActor.assumeIsolated { handler() } }
}

extension NSColor {
    /// "#rrggbb"
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

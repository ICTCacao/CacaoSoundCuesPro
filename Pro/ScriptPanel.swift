import AppKit
import CacaoSoundCuesCore
import SwiftUI

// 台本のパネル。台本を目で追いながら、自分でページを送る（← → ／ 下の ‹ ›）。
// 台本の文字には何も載せず（紙の台本と同じ見た目）、ページの下（横書きは右）の「きっかけの帯」に、
// きっかけの位置から線を引き、押すキー・名前・メモを横書きで出す（音響台本の書き方）。次のページにきっかけがあれば下に出す

/// 主画面の横に台本のパネルを並べる
struct ProScriptSplit<Content: View>: View {
    @ViewBuilder var content: Content
    private var pro: ProModel { ProModel.shared }

    var body: some View {
        if pro.showPanel {
            HSplitView {
                ScriptPanel()
                    .frame(minWidth: 280, idealWidth: 380)
                    .background(SplitPersistence(key: "pro.split.script"))
                content
                    .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            // 畳んだときは左に細い帯を残し、押すと開く
            HStack(spacing: 0) {
                FoldedScriptStrip()
                ThemeDivider()
                content
            }
        }
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
            if let script = pro.script {
                GeometryReader { geo in
                    ScriptPager(script: script,
                                size: geo.size,
                                vertical: pro.data.vertical,
                                fontSize: pro.data.fontSize,
                                links: pro.data.links,
                                marks: pro.allMarks(),
                                active: pro.activeCueIDs,
                                selected: pro.selected,
                                keyCues: model.show.keyCues,
                                sequences: model.show.sequences,
                                page: pro.page)
                }
                .background(Color(nsColor: .textBackgroundColor))
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
                    Menu(L("文字の大きさ")) {
                        ForEach([12.0, 14, 16, 18, 20, 24], id: \.self) { s in
                            Button { pro.setFontSize(s) } label: {
                                Text("\(Int(s))") + Text(pro.data.fontSize == s ? " ✓" : "")
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
            if !next.isEmpty {
                HStack(spacing: 6) {
                    Text(L("次のページ"))
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .background(Capsule().fill(Color.orange.opacity(0.3)))
                    ForEach(next) { m in
                        MarkBadge(mark: m, lit: pro.activeCueIDs.contains(m.id))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// 次のページにあるきっかけ（台本のパネルがページの行を教える）
    private var nextPageMarks: [CueMark] {
        ScriptPageIndex.shared.lines(onPage: pro.page + 1).flatMap { pro.marks(for: $0) }
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
    let links: [String: CueAnchor]
    /// 帯に描くきっかけ（始まり・終わり・メモ）
    let marks: [CueMark]
    let active: Set<UUID>
    let selected: CueAnchor?
    let keyCues: [KeyCue]
    let sequences: [CueSequence]
    let page: Int

    func makeNSView(context: Context) -> PagerView { PagerView() }

    func updateNSView(_ view: PagerView, context: Context) {
        let pro = ProModel.shared
        // 組み直しが要るのは、台本・大きさ・書き方向・文字の大きさが変わったとき（きっかけは帯に描くだけなので組み直さない）
        let layoutKey = LayoutKey(script: script, size: size, vertical: vertical, fontSize: fontSize)
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
        view.show(page: min(pro.page, max(0, view.pageCount - 1)), marks: marks, active: active)
    }

    struct LayoutKey: Equatable {
        var script: ScriptDocument
        var size: CGSize
        var vertical: Bool
        var fontSize: Double
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
    private let band = CueBandView()
    private var shown = -1
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

    var pageCount: Int { textViews.count }

    override init(frame: NSRect) {
        super.init(frame: frame)
        storage.addLayoutManager(layoutManager)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func build(_ key: ScriptPager.LayoutKey) {
        layoutKey = key
        pageSize = CGSize(width: max(100, key.size.width), height: max(100, key.size.height))
        let inner = CGSize(width: pageSize.width - inset * 2, height: pageSize.height - inset * 2)
        // きっかけの帯の分を空ける（縦書きは下、横書きは右）
        bandThickness = key.vertical ? min(170, max(90, pageSize.height * 0.3)) : min(260, max(150, pageSize.width * 0.38))
        // 1 行の長さに「人物名欄 ＋ 本文」の字数が入る大きさにする（PDF の書き出しと同じ）
        let lineChars = Double(key.script.characterLength + key.script.bodyLength)
        let lineLength = Double((key.vertical ? inner.height : inner.width) - bandThickness)
        fontSize = max(6, min(key.fontSize, (lineLength / (lineChars + 0.3) * 2).rounded(.down) / 2))
        let lineEnd = CGFloat(lineChars * fontSize + fontSize * 0.3)

        storage.setAttributedString(makeText(key.script, fontSize: fontSize))
        for tv in textViews { tv.removeFromSuperview() }
        textViews = []
        pageRanges = []
        while !layoutManager.textContainers.isEmpty { layoutManager.removeTextContainer(at: 0) }
        shown = -1
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
            layoutManager.ensureLayout(for: container)
            let range = layoutManager.characterRange(forGlyphRange: layoutManager.glyphRange(for: container), actualGlyphRange: nil)
            pageRanges.append(range)
            // このページにある行（台本の順）
            pages.append(lineRanges.filter { NSIntersectionRange($0.value, range).length > 0 }
                .sorted { $0.value.location < $1.value.location }.map(\.key))
            if range.length == 0 || NSMaxRange(range) >= storage.length || textViews.count > 3000 { break }
        } while true
        ScriptPageIndex.shared.pages = pages
    }

    func show(page: Int, marks: [CueMark], active: Set<UUID>) {
        guard textViews.indices.contains(page) else { return }
        if page != shown {
            if textViews.indices.contains(shown) { textViews[shown].removeFromSuperview() }
            let tv = textViews[page]
            tv.frame = NSRect(origin: .zero, size: pageSize)
            addSubview(tv, positioned: .below, relativeTo: band.superview == nil ? nil : band)
            shown = page
        }
        if band.superview == nil { addSubview(band) }
        let vertical = layoutKey?.vertical ?? true
        band.frame = vertical
            ? NSRect(x: 0, y: pageSize.height - bandThickness, width: pageSize.width, height: bandThickness)
            : NSRect(x: pageSize.width - bandThickness, y: 0, width: bandThickness, height: pageSize.height)
        // 帯の位置は、文字の画面上の位置から決めるので、表示が済んでから
        DispatchQueue.main.async { [weak self] in self?.updateBand(marks: marks, active: active) }
    }

    // MARK: きっかけの帯

    /// このページのきっかけを、帯に描く形にする
    private func updateBand(marks: [CueMark], active: Set<UUID>) {
        guard textViews.indices.contains(shown), window != nil else { return }
        let tv = textViews[shown]
        let range = pageRanges[shown]
        let vertical = layoutKey?.vertical ?? true
        // 線の向きの位置: 縦書きは x（右から左へ進む）、横書きは y（上から下へ進む）。帯の中の座標で
        let startEdge = vertical ? pageSize.width - inset : inset
        let endEdge = vertical ? inset : pageSize.height - inset
        func pos(_ index: Int) -> CGFloat? {
            guard NSLocationInRange(index, range) else { return nil }
            var screen = tv.firstRect(forCharacterRange: NSRange(location: index, length: 1), actualRange: nil)
            guard let win = window, screen.width > 0 || screen.height > 0 else { return nil }
            screen = win.convertFromScreen(screen)
            let r = convert(screen, from: nil)
            return vertical ? r.midX : r.midY
        }
        var items: [CueBandView.Item] = []
        for m in marks {
            guard let s = location(of: m.start) else { continue }
            let e = m.end.flatMap { location(of: $0) }
            let lit = active.contains(m.id)
            if let e {
                let (a, b) = s <= e ? (s, e) : (e, s)
                // このページにかかっていなければ描かない
                guard a < NSMaxRange(range), b >= range.location else { continue }
                let from = pos(a) ?? startEdge
                let to = pos(b) ?? endEdge
                items.append(.init(mark: m, start: from, end: to, startsHere: pos(a) != nil, endsHere: pos(b) != nil, lit: lit))
            } else if let p = pos(s) {
                items.append(.init(mark: m, start: p, end: nil, startsHere: true, endsHere: false, lit: lit))
            }
        }
        band.vertical = vertical
        band.items = items
        band.needsDisplay = true
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
        if textViews.indices.contains(shown) { textViews[shown].needsDisplay = true }
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

    private func makeText(_ script: ScriptDocument, fontSize: Double) -> NSAttributedString {
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
                para.headIndent = CGFloat(nameW + bodyIndent) * fs
                para.lineSpacing = fs * 0.2
                para.paragraphSpacing = fs * 0.25
                // 黒はダークモードでも読めるよう、文字の標準の色にする
                let hex = (style?.color ?? "#000000").lowercased()
                let color = hex == "#000000" ? NSColor.textColor : (NSColor(hex: hex) ?? .textColor)
                let attrs: [NSAttributedString.Key: Any] = [.font: body, .foregroundColor: color, .paragraphStyle: para, .scriptLine: line.uid]

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
    }

    var vertical = true
    var items: [Item] = []

    override var isFlipped: Bool { true }

    private let keyFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
    private let nameFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    private let memoFont = NSFont.systemFont(ofSize: 11)
    private let endFont = NSFont.systemFont(ofSize: 12, weight: .bold)

    override func draw(_ dirtyRect: NSRect) {
        // 台本との境の線
        NSColor.separatorColor.setFill()
        if vertical { NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill() } else { NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill() }
        if vertical { drawVertical() } else { drawHorizontal() }
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
        var laneEnds = [CGFloat](repeating: .greatestFiniteMagnitude, count: lanes)   // 各段の、いちばん左に使った位置
        // 始まりが右（ページの先）のものから順に段を決める
        for item in items.sorted(by: { $0.start > $1.start }) {
            let s = labelSize(item.mark, continued: !item.startsHere)
            let right = item.start
            var left = min(right - s.total.width, item.end ?? right)
            if item.endsHere { left -= (item.mark.endLabel as NSString).size(withAttributes: [.font: endFont]).width + 6 }
            let lane = laneEnds.firstIndex { right + 6 <= $0 } ?? (lanes - 1)
            laneEnds[lane] = min(laneEnds[lane], left)
            let top = 6 + CGFloat(lane) * laneHeight
            let color = item.mark.color.withAlphaComponent(item.lit ? 1 : 0.7)
            color.setFill()
            let thick: CGFloat = item.lit ? 8 : 5
            if let end = item.end {
                NSRect(x: min(end, right), y: top + 4, width: abs(right - end), height: thick).fill()
                if item.endsHere {
                    NSRect(x: end - 1.5, y: top, width: 3, height: thick + 8).fill()
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
            }
            drawLabel(item, at: NSPoint(x: right - s.total.width, y: top + thick + 8))
        }
    }

    // 横書き: 線は縦（上から下）。線は左の細い段に並べ、ラベルは右に、始まりの高さにそろえて並べる
    private func drawHorizontal() {
        let slotWidth: CGFloat = 14
        let slots = 4
        var slotEnds = [CGFloat](repeating: -.greatestFiniteMagnitude, count: slots)   // 各段の、いちばん下に使った位置
        var labelBottom: CGFloat = 0
        let labelX = 10 + slotWidth * CGFloat(slots) + 6
        for item in items.sorted(by: { $0.start < $1.start }) {
            let s = labelSize(item.mark, continued: !item.startsHere)
            let top = item.start
            let bottom = item.end ?? top + 14
            let slot = slotEnds.firstIndex { top - 6 >= $0 } ?? (slots - 1)
            slotEnds[slot] = max(slotEnds[slot], bottom)
            let x = 10 + slotWidth * CGFloat(slot)
            let color = item.mark.color.withAlphaComponent(item.lit ? 1 : 0.7)
            color.setFill()
            let thick: CGFloat = item.lit ? 7 : 4
            NSRect(x: x, y: min(top, bottom), width: thick, height: abs(bottom - top)).fill()
            if item.startsHere { NSRect(x: x - 4, y: top - 1.5, width: thick + 8, height: 3).fill() }
            if item.end != nil, item.endsHere {
                NSRect(x: x - 4, y: bottom - 1.5, width: thick + 8, height: 3).fill()
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

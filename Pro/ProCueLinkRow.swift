import CacaoSoundCuesCore
import SwiftUI

/// インスペクタの「きっかけ」の行: このキー・曲が結びついている台本の位置
struct ProCueLinkRow: View {
    @Environment(AppModel.self) private var model
    let cueID: UUID
    private var pro: ProModel { ProModel.shared }

    var body: some View {
        // 出力の系統（系統が 2 つ以上あるとき）
        ProOutputRow(cueID: cueID)
        // MIDI で鳴らす・MIDI を送る
        ProMIDIRow(cueID: cueID)
        if pro.hasScript {
            VStack(alignment: .leading, spacing: 6) {
            if let anchor = pro.anchor(for: cueID) {
                // 1 段目: きっかけの位置（と、ほかに何か所あるか）
                HStack(spacing: 8) {
                    Label(L("きっかけ"), systemImage: "text.book.closed")
                        .fixedSize()
                    if let text = pro.summary(anchor) {
                        Text(text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else {
                        Text(L("台本の中に見つかりません（台本が直された？）"))
                            .foregroundStyle(.orange)
                    }
                    Spacer(minLength: 4)
                    // 同じ音を別の場所でも鳴らす（2 か所目から）
                    let others = pro.linkIDs(of: cueID).count - 1
                    if others > 0 {
                        Text(L("ほかに %d か所", others))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
                // 2 段目: ボタン（横に詰めると名前が省かれて読めないため、段を分ける）
                HStack(spacing: 8) {
                    let others = pro.linkIDs(of: cueID).count - 1
                    if pro.summary(anchor) != nil {
                        Button { reveal(anchor) } label: { Label(L("台本で見る"), systemImage: "eye") }
                    }
                    Spacer(minLength: 4)
                    if !model.showMode {
                        if let sel = pro.selected, sel != anchor {
                            Button { pro.addLink(cueID, at: sel) } label: { Label(L("選んだ位置にも足す"), systemImage: "plus.circle") }
                                .help(L("同じ音を、台本の別の場所でも鳴らす"))
                            if others == 0 {
                                Button { pro.link(cueID, to: sel) } label: { Label(L("選んだ位置へ移す"), systemImage: "arrow.right.circle") }
                            }
                        }
                        Button { pro.unlink(cueID) } label: { Label(L("外す"), systemImage: "xmark") }
                            .help(others > 0 ? L("1 か所目を外す（2 か所目が 1 か所目になる）") : L("台本との結びつきを外す"))
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 8) {
                    Label(L("きっかけ"), systemImage: "text.book.closed")
                        .fixedSize()
                    Text(pro.selected != nil && !model.showMode
                         ? L("台本で選んだ位置に結びつけられます")
                         : L("台本の文字をクリックして位置を選ぶか、右クリックで結びつけます"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    if let sel = pro.selected, !model.showMode {
                        Button { pro.link(cueID, to: sel) } label: { Label(L("選んだ位置に結びつける"), systemImage: "link") }
                    }
                }
            }
            if pro.anchor(for: cueID) != nil {
                HStack(spacing: 8) {
                    Text(L("メモ")).fixedSize()
                    TextField(L("帯のラベルの下に出す（例 Piano・2回目は小さく）"),
                              text: Binding(get: { pro.memo(for: cueID) }, set: { pro.setMemo(cueID, $0) }))
                        .textFieldStyle(.roundedBorder)
                        .disabled(model.showMode)
                    if let end = pro.end(for: cueID), let text = pro.summary(end, around: 6) {
                        Text(L("止める: %@", text))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.08)))
        }
    }

    private func reveal(_ anchor: CueAnchor) {
        pro.showPanel = true
        pro.selected = anchor
        pro.revealRequest = anchor.line
    }
}

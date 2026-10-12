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
        if let script = pro.script {
            VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label(L("きっかけ"), systemImage: "text.book.closed")
                    .fixedSize()
                if let anchor = pro.anchor(for: cueID) {
                    if let text = script.summary(anchor) {
                        Text(text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                        Button { reveal(anchor) } label: { Label(L("台本で見る"), systemImage: "eye") }
                    } else {
                        Text(L("台本の中に見つかりません（台本が直された？）"))
                            .foregroundStyle(.orange)
                        Spacer(minLength: 4)
                    }
                    if !model.showMode {
                        if let sel = pro.selected, sel != anchor {
                            Button { pro.link(cueID, to: sel) } label: { Label(L("選んだ位置へ移す"), systemImage: "arrow.right.circle") }
                        }
                        Button { pro.unlink(cueID) } label: { Label(L("外す"), systemImage: "xmark") }
                    }
                } else {
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
                    if let end = pro.end(for: cueID), let text = script.summary(end, around: 6) {
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

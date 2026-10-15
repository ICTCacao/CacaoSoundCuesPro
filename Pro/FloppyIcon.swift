import SwiftUI

/// 「保存」の絵（昔のフロッピーディスク）。SF Symbols に無いので自分で描く。
/// 上の帯の「開く」（folder）と同じ線の太さ・色（foregroundStyle）で、輪郭だけ描く
struct FloppyIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let lw: CGFloat = 1.3
            // 本体（右上の角を落とす）
            var body = Path()
            body.move(to: CGPoint(x: 0.5, y: 0.5))
            body.addLine(to: CGPoint(x: w - 3.5, y: 0.5))
            body.addLine(to: CGPoint(x: w - 0.5, y: 3.5))
            body.addLine(to: CGPoint(x: w - 0.5, y: h - 0.5))
            body.addLine(to: CGPoint(x: 0.5, y: h - 0.5))
            body.closeSubpath()
            ctx.stroke(body, with: .foreground, style: StrokeStyle(lineWidth: lw, lineJoin: .round))
            // 上のシャッター（金属の板）と、そのスリット
            let shutter = CGRect(x: w * 0.27, y: 0.5, width: w * 0.42, height: h * 0.32)
            ctx.stroke(Path(shutter), with: .foreground, lineWidth: lw)
            ctx.fill(Path(CGRect(x: shutter.maxX - w * 0.14, y: 2, width: w * 0.07, height: shutter.height - 3)), with: .foreground)
            // 下のラベル
            let label = CGRect(x: w * 0.2, y: h * 0.58, width: w * 0.6, height: h * 0.42 - 0.5)
            ctx.stroke(Path(label), with: .foreground, lineWidth: lw)
        }
        .frame(width: 15, height: 14)
    }
}

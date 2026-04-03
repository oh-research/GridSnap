import SwiftUI

/// SVG gridsnap_icon.svg와 동일한 디자인의 SwiftUI 앱 아이콘 뷰
struct AppIconView: View {
    var body: some View {
        Canvas { context, size in
            let s = size.width  // 정사각형 가정

            // 배경: 인디고→퍼플 그라데이션 둥근 사각형
            let bgRect = CGRect(origin: .zero, size: size)
            let bgPath = RoundedRectangle(cornerRadius: s * 0.215).path(in: bgRect)
            context.fill(bgPath, with: .linearGradient(
                Gradient(colors: [Color(hex: 0x4F46E5), Color(hex: 0x7C3AED)]),
                startPoint: .zero,
                endPoint: CGPoint(x: s, y: s)
            ))

            // 안쪽 테두리
            let inset = s * 0.039
            let innerRect = bgRect.insetBy(dx: inset, dy: inset)
            let innerPath = RoundedRectangle(cornerRadius: s * 0.184).path(in: innerRect)
            context.stroke(innerPath, with: .color(.white.opacity(0.1)), lineWidth: s * 0.004)

            // 3x3 그리드 선
            let pad = s * 0.078
            let gridStart = pad
            let gridEnd = s - pad
            let gridW = gridEnd - gridStart
            let lineWidth = s * 0.023

            for i in 1...2 {
                let pos = gridStart + gridW * CGFloat(i) / 3.0
                // 세로선
                var vPath = Path()
                vPath.move(to: CGPoint(x: pos, y: gridStart))
                vPath.addLine(to: CGPoint(x: pos, y: gridEnd))
                context.stroke(vPath, with: .color(.white.opacity(0.35)),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                // 가로선
                var hPath = Path()
                hPath.move(to: CGPoint(x: gridStart, y: pos))
                hPath.addLine(to: CGPoint(x: gridEnd, y: pos))
                context.stroke(hPath, with: .color(.white.opacity(0.35)),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }

            // 유리 윈도우 (좌상단 2x2 영역)
            let winX = s * 0.211
            let winY = s * 0.211
            let winW = s * 0.441
            let winH = s * 0.441
            let winCorner = s * 0.039
            let winRect = CGRect(x: winX, y: winY, width: winW, height: winH)
            let winPath = RoundedRectangle(cornerRadius: winCorner).path(in: winRect)

            // 윈도우 본체 (유리 그라데이션)
            context.fill(winPath, with: .linearGradient(
                Gradient(colors: [
                    Color(hex: 0xCCDCF0).opacity(0.9),
                    Color(hex: 0x8AAAD0).opacity(0.7)
                ]),
                startPoint: CGPoint(x: winX, y: winY),
                endPoint: CGPoint(x: winX, y: winY + winH)
            ))

            // 트래픽 라이트
            let dotR = s * 0.018
            let dotY = winY + winH * 0.155
            let dotX0 = winX + winW * 0.155
            let dotGap = s * 0.055

            let dots: [(Color, CGFloat)] = [
                (Color(hex: 0xFF5F57), 0),
                (Color(hex: 0xFFBD2E), 1),
                (Color(hex: 0x28C840), 2),
            ]
            for (color, i) in dots {
                let cx = dotX0 + i * dotGap
                let dotRect = CGRect(x: cx - dotR, y: dotY - dotR, width: dotR * 2, height: dotR * 2)
                context.fill(Circle().path(in: dotRect), with: .color(color.opacity(0.9)))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 0))
    }
}

extension Color {
    init(hex: UInt, opacity: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

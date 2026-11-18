import SwiftUI

/// 极简主机线稿（3/4 视角），用 Canvas 自绘，不依赖任何图片或 emoji。
struct ConsoleSilhouette: View {
    var kind: ConsoleKind
    var lineWidth: CGFloat = 1.2
    var tint: Color = Theme.Palette.textPrimary
    var dimmed: Bool = false
    var dashed: Bool = false

    var body: some View {
        Canvas { context, size in
            let stroke = tint.opacity(dimmed ? 0.35 : 0.9)
            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round,
                                    dash: dashed ? [4, 4] : [])
            switch kind {
            case .seriesX, .unknown:
                drawSeriesX(context: &context, size: size, stroke: stroke, style: style)
            case .seriesS:
                drawSeriesS(context: &context, size: size, stroke: stroke, style: style)
            case .one:
                drawOne(context: &context, size: size, stroke: stroke, style: style)
            }
        }
        .aspectRatio(kind.aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }

    // MARK: Series X：竖立长方体，顶部圆形散热孔点阵

    private func drawSeriesX(context: inout GraphicsContext, size: CGSize, stroke: Color, style: StrokeStyle) {
        let w = size.width, h = size.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }

        // 地面投影
        context.fill(Path(ellipseIn: CGRect(x: 0.10 * w, y: 0.93 * h, width: 0.82 * w, height: 0.07 * h)),
                     with: .color(.black.opacity(0.45)))

        let front = polygon([p(0.16, 0.22), p(0.68, 0.22), p(0.68, 0.96), p(0.16, 0.96)])
        let top = polygon([p(0.16, 0.22), p(0.68, 0.22), p(0.86, 0.08), p(0.34, 0.08)])
        let side = polygon([p(0.68, 0.22), p(0.86, 0.08), p(0.86, 0.83), p(0.68, 0.96)])

        context.fill(top, with: .color(stroke.opacity(0.10)))
        context.fill(front, with: .linearGradient(
            Gradient(colors: [stroke.opacity(0.07), stroke.opacity(0.02)]),
            startPoint: p(0.4, 0.22), endPoint: p(0.4, 0.96)))
        context.fill(side, with: .color(stroke.opacity(0.03)))

        context.stroke(front, with: .color(stroke), style: style)
        context.stroke(top, with: .color(stroke), style: style)
        context.stroke(side, with: .color(stroke), style: style)

        // 顶部散热孔：椭圆 + 点阵
        let ventCenter = p(0.51, 0.15)
        let rx = 0.17 * w, ry = 0.045 * h
        let vent = Path(ellipseIn: CGRect(x: ventCenter.x - rx, y: ventCenter.y - ry, width: rx * 2, height: ry * 2))
        context.fill(vent, with: .color(.black.opacity(0.55)))
        context.stroke(vent, with: .color(stroke.opacity(0.6)), lineWidth: lineWidth * 0.7)
        let dot = max(0.8, lineWidth * 0.9)
        for row in -2...2 {
            for col in -6...6 {
                let x = CGFloat(col) / 6.6
                let y = CGFloat(row) / 2.6
                guard x * x + y * y < 0.85 else { continue }
                let c = CGPoint(x: ventCenter.x + x * rx, y: ventCenter.y + y * ry)
                context.fill(Path(ellipseIn: CGRect(x: c.x - dot / 2, y: c.y - dot / 2, width: dot, height: dot)),
                             with: .color(stroke.opacity(0.55)))
            }
        }

        // 电源键
        let pwr = p(0.22, 0.27)
        context.stroke(Path(ellipseIn: CGRect(x: pwr.x - 2.5, y: pwr.y - 2.5, width: 5, height: 5)),
                       with: .color(stroke.opacity(0.8)), lineWidth: lineWidth * 0.8)
        // 光驱槽
        var slot = Path()
        slot.move(to: p(0.22, 0.40)); slot.addLine(to: p(0.22, 0.62))
        context.stroke(slot, with: .color(stroke.opacity(0.45)), lineWidth: lineWidth * 0.8)
    }

    // MARK: Series S：扁盒 + 圆形进风口

    private func drawSeriesS(context: inout GraphicsContext, size: CGSize, stroke: Color, style: StrokeStyle) {
        let w = size.width, h = size.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }

        context.fill(Path(ellipseIn: CGRect(x: 0.06 * w, y: 0.86 * h, width: 0.88 * w, height: 0.10 * h)),
                     with: .color(.black.opacity(0.45)))

        let front = polygon([p(0.06, 0.30), p(0.76, 0.30), p(0.76, 0.88), p(0.06, 0.88)])
        let top = polygon([p(0.06, 0.30), p(0.76, 0.30), p(0.92, 0.14), p(0.22, 0.14)])
        let side = polygon([p(0.76, 0.30), p(0.92, 0.14), p(0.92, 0.72), p(0.76, 0.88)])

        context.fill(front, with: .color(stroke.opacity(0.14)))
        context.fill(top, with: .color(stroke.opacity(0.20)))
        context.fill(side, with: .color(stroke.opacity(0.08)))
        context.stroke(front, with: .color(stroke), style: style)
        context.stroke(top, with: .color(stroke), style: style)
        context.stroke(side, with: .color(stroke), style: style)

        // 圆形进风口
        let c = p(0.54, 0.59)
        let r = 0.20 * h
        let vent = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        context.fill(vent, with: .color(.black.opacity(0.85)))
        context.stroke(vent, with: .color(stroke.opacity(0.6)), lineWidth: lineWidth * 0.7)
        let dot = max(0.8, lineWidth * 0.8)
        for ring in 1...4 {
            let rr = r * CGFloat(ring) / 4.6
            let count = ring * 8
            for i in 0..<count {
                let a = CGFloat(i) / CGFloat(count) * 2 * .pi
                let pt = CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
                context.fill(Path(ellipseIn: CGRect(x: pt.x - dot / 2, y: pt.y - dot / 2, width: dot, height: dot)),
                             with: .color(stroke.opacity(0.45)))
            }
        }
        // 电源键
        let pwr = p(0.13, 0.40)
        context.stroke(Path(ellipseIn: CGRect(x: pwr.x - 2.5, y: pwr.y - 2.5, width: 5, height: 5)),
                       with: .color(stroke.opacity(0.8)), lineWidth: lineWidth * 0.8)
    }

    // MARK: One：横置机身

    private func drawOne(context: inout GraphicsContext, size: CGSize, stroke: Color, style: StrokeStyle) {
        let w = size.width, h = size.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }

        context.fill(Path(ellipseIn: CGRect(x: 0.04 * w, y: 0.74 * h, width: 0.90 * w, height: 0.12 * h)),
                     with: .color(.black.opacity(0.45)))

        let front = polygon([p(0.04, 0.44), p(0.82, 0.44), p(0.82, 0.76), p(0.04, 0.76)])
        let top = polygon([p(0.04, 0.44), p(0.82, 0.44), p(0.96, 0.24), p(0.18, 0.24)])
        let side = polygon([p(0.82, 0.44), p(0.96, 0.24), p(0.96, 0.56), p(0.82, 0.76)])

        context.fill(top, with: .color(stroke.opacity(0.10)))
        context.fill(front, with: .color(stroke.opacity(0.05)))
        context.fill(side, with: .color(stroke.opacity(0.03)))
        context.stroke(front, with: .color(stroke), style: style)
        context.stroke(top, with: .color(stroke), style: style)
        context.stroke(side, with: .color(stroke), style: style)

        // 顶面分割线（亮面 / 散热面）
        var split = Path()
        split.move(to: p(0.32, 0.44)); split.addLine(to: p(0.46, 0.24))
        context.stroke(split, with: .color(stroke.opacity(0.5)), lineWidth: lineWidth * 0.8)

        // 光驱槽
        var slot = Path()
        slot.move(to: p(0.10, 0.54)); slot.addLine(to: p(0.42, 0.54))
        context.stroke(slot, with: .color(stroke.opacity(0.5)), lineWidth: lineWidth * 0.8)

        // 电源标志
        let pwr = p(0.74, 0.56)
        context.stroke(Path(ellipseIn: CGRect(x: pwr.x - 3, y: pwr.y - 3, width: 6, height: 6)),
                       with: .color(stroke.opacity(0.8)), lineWidth: lineWidth * 0.8)
    }

    private func polygon(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for pt in points.dropFirst() { path.addLine(to: pt) }
        path.closeSubpath()
        return path
    }
}

extension ConsoleKind {
    var aspectRatio: CGFloat {
        switch self {
        case .seriesX, .unknown: return 0.78
        case .seriesS: return 1.25
        case .one: return 1.8
        }
    }
}

#Preview {
    HStack(spacing: 30) {
        ConsoleSilhouette(kind: .seriesX).frame(height: 140)
        ConsoleSilhouette(kind: .seriesS).frame(height: 140)
        ConsoleSilhouette(kind: .one).frame(height: 140)
    }
    .padding(40)
    .background(Theme.Palette.background)
}

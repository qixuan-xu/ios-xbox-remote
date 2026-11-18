import SwiftUI

/// 手柄外形轮廓（正视），单位坐标绘制。
struct ControllerOutlineShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * w, y: rect.minY + y * h) }

        var path = Path()
        path.move(to: p(0.50, 0.13))
        // 顶部右半
        path.addCurve(to: p(0.80, 0.12), control1: p(0.62, 0.13), control2: p(0.72, 0.08))
        // 右肩
        path.addCurve(to: p(0.95, 0.42), control1: p(0.90, 0.16), control2: p(0.94, 0.30))
        // 右侧向下到握把底
        path.addCurve(to: p(0.86, 0.94), control1: p(0.98, 0.62), control2: p(0.96, 0.90))
        // 握把底部圆弧
        path.addCurve(to: p(0.70, 0.80), control1: p(0.78, 0.98), control2: p(0.74, 0.90))
        // 内侧回到中部
        path.addCurve(to: p(0.50, 0.70), control1: p(0.65, 0.70), control2: p(0.58, 0.70))
        // 对称左半
        path.addCurve(to: p(0.30, 0.80), control1: p(0.42, 0.70), control2: p(0.35, 0.70))
        path.addCurve(to: p(0.14, 0.94), control1: p(0.26, 0.90), control2: p(0.22, 0.98))
        path.addCurve(to: p(0.05, 0.42), control1: p(0.04, 0.90), control2: p(0.02, 0.62))
        path.addCurve(to: p(0.20, 0.12), control1: p(0.06, 0.30), control2: p(0.10, 0.16))
        path.addCurve(to: p(0.50, 0.13), control1: p(0.28, 0.08), control2: p(0.38, 0.13))
        path.closeSubpath()
        return path
    }
}

/// 手柄线稿：外形 + 摇杆、十字键、ABXY、中心键。
struct ControllerGlyph: View {
    var lineWidth: CGFloat = 1.2
    var tint: Color = Theme.Palette.textPrimary
    /// 高亮某个部件（键位映射页用）
    var highlight: ControllerPart? = nil

    enum ControllerPart: Hashable {
        case leftStick, rightStick, dpad, faceButtons, nexus, shoulders, menuButtons
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let r = w * 0.065
            ZStack {
                ControllerOutlineShape()
                    .fill(LinearGradient(colors: [tint.opacity(0.08), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                ControllerOutlineShape()
                    .stroke(tint.opacity(0.9), style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))

                // 左摇杆
                stick(at: CGPoint(x: w * 0.29, y: h * 0.36), r: r, part: .leftStick)
                // 右摇杆
                stick(at: CGPoint(x: w * 0.62, y: h * 0.55), r: r, part: .rightStick)
                // 十字键
                DPadShape()
                    .stroke(color(for: .dpad), style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
                    .frame(width: r * 2.2, height: r * 2.2)
                    .position(x: w * 0.38, y: h * 0.55)
                // ABXY
                ForEach(0..<4, id: \.self) { i in
                    let offsets: [CGPoint] = [CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 0), CGPoint(x: -1, y: 0), CGPoint(x: 0, y: -1)]
                    Circle()
                        .stroke(color(for: .faceButtons), lineWidth: lineWidth)
                        .frame(width: r * 0.8, height: r * 0.8)
                        .position(x: w * 0.72 + offsets[i].x * r * 1.05, y: h * 0.36 + offsets[i].y * r * 1.05)
                }
                // 中心键
                Circle()
                    .stroke(color(for: .nexus), lineWidth: lineWidth)
                    .frame(width: r * 1.1, height: r * 1.1)
                    .position(x: w * 0.5, y: h * 0.25)
                // View / Menu
                ForEach([-1.0, 1.0], id: \.self) { side in
                    Capsule()
                        .stroke(color(for: .menuButtons), lineWidth: lineWidth * 0.8)
                        .frame(width: r * 0.7, height: r * 0.45)
                        .position(x: w * (0.5 + side * 0.09), y: h * 0.37)
                }
                // 肩键
                if highlight == .shoulders {
                    ForEach([0.2, 0.8], id: \.self) { x in
                        Capsule()
                            .fill(Theme.Palette.accent.opacity(0.8))
                            .frame(width: w * 0.16, height: max(2, lineWidth * 2))
                            .position(x: w * x, y: h * 0.07)
                    }
                }
            }
        }
        .aspectRatio(1.45, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func stick(at point: CGPoint, r: CGFloat, part: ControllerPart) -> some View {
        ZStack {
            Circle().stroke(color(for: part), lineWidth: lineWidth)
            Circle().stroke(color(for: part).opacity(0.5), lineWidth: lineWidth * 0.7).padding(r * 0.35)
        }
        .frame(width: r * 2, height: r * 2)
        .position(point)
    }

    private func color(for part: ControllerPart) -> Color {
        highlight == part ? Theme.Palette.accent : tint.opacity(0.75)
    }
}

/// 十字键形状
struct DPadShape: Shape {
    var armWidthRatio: CGFloat = 0.34
    func path(in rect: CGRect) -> Path {
        let a = min(rect.width, rect.height) * armWidthRatio
        let cx = rect.midX, cy = rect.midY
        let half = a / 2
        var path = Path()
        path.move(to: CGPoint(x: cx - half, y: rect.minY))
        path.addLine(to: CGPoint(x: cx + half, y: rect.minY))
        path.addLine(to: CGPoint(x: cx + half, y: cy - half))
        path.addLine(to: CGPoint(x: rect.maxX, y: cy - half))
        path.addLine(to: CGPoint(x: rect.maxX, y: cy + half))
        path.addLine(to: CGPoint(x: cx + half, y: cy + half))
        path.addLine(to: CGPoint(x: cx + half, y: rect.maxY))
        path.addLine(to: CGPoint(x: cx - half, y: rect.maxY))
        path.addLine(to: CGPoint(x: cx - half, y: cy + half))
        path.addLine(to: CGPoint(x: rect.minX, y: cy + half))
        path.addLine(to: CGPoint(x: rect.minX, y: cy - half))
        path.addLine(to: CGPoint(x: cx - half, y: cy - half))
        path.closeSubpath()
        return path
    }
}

/// 中心（主页）键字形：圆环 + 两道交叉弧线
struct NexusGlyph: View {
    var lineWidth: CGFloat = 1.5
    var tint: Color = Theme.Palette.textPrimary

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                Circle().stroke(tint, lineWidth: lineWidth)
                NexusCrossShape()
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .padding(s * 0.22)
            }
            .frame(width: s, height: s)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct NexusCrossShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        // 左上到右下，向中心内收的弧线
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX + rect.width * 0.12, y: rect.midY - rect.height * 0.12))
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY), control: CGPoint(x: rect.midX - rect.width * 0.12, y: rect.midY - rect.height * 0.12))
        return p
    }
}

/// 手机线稿（竖向，带灵动岛）
struct PhoneGlyph: View {
    var lineWidth: CGFloat = 1.2
    var tint: Color = Theme.Palette.textPrimary
    var landscape: Bool = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let corner = min(w, h) * 0.16
            ZStack {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(LinearGradient(colors: [tint.opacity(0.08), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(tint.opacity(0.9), lineWidth: lineWidth)
                RoundedRectangle(cornerRadius: corner * 0.8, style: .continuous)
                    .stroke(tint.opacity(0.25), lineWidth: lineWidth * 0.6)
                    .padding(min(w, h) * 0.05)
                Capsule()
                    .fill(tint.opacity(0.6))
                    .frame(width: landscape ? min(w, h) * 0.09 : w * 0.28,
                           height: landscape ? h * 0.28 : min(w, h) * 0.09)
                    .position(x: landscape ? w * 0.08 : w / 2, y: landscape ? h / 2 : h * 0.08)
            }
        }
        .aspectRatio(landscape ? 2.1 : 0.48, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// App 标志：受光圆环 + 手柄线稿
struct AppMark: View {
    var size: CGFloat = 88

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Theme.Palette.accent.opacity(0.18), .clear],
                                     center: .center, startRadius: 0, endRadius: size * 0.6))
            Circle()
                .stroke(AngularGradient(colors: [Theme.Palette.accent, Theme.Palette.accentDeep.opacity(0.4),
                                                 Theme.Palette.accent.opacity(0.9), Theme.Palette.accent],
                                        center: .center),
                        lineWidth: max(1.5, size * 0.025))
            ControllerGlyph(lineWidth: max(1, size * 0.016))
                .frame(width: size * 0.56)
                .offset(y: size * 0.02)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 30) {
        AppMark(size: 120)
        ControllerGlyph(highlight: .faceButtons).frame(width: 220)
        NexusGlyph().frame(width: 40)
        PhoneGlyph().frame(height: 120)
    }
    .padding(40)
    .background(Theme.Palette.background)
}

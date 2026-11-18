import SwiftUI

/// 屏幕按键的视觉：暗色玻璃 + 发丝描边；默认不铺色，按下时亮起对应颜色的柔光并轻微缩小。
struct GlassControl<Label: View, S: InsettableShape>: View {
    var shape: S
    var pressed: Bool
    var glow: Color = .white
    @ViewBuilder var label: Label

    var body: some View {
        ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(Color.black.opacity(0.28))
            shape.fill(glow.opacity(pressed ? 0.38 : 0))
            shape.strokeBorder(
                LinearGradient(colors: [Color.white.opacity(pressed ? 0.6 : 0.28), Color.white.opacity(pressed ? 0.25 : 0.06)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 0.75
            )
            label
                .foregroundStyle(Color.white.opacity(pressed ? 1 : 0.85))
        }
        .shadow(color: glow.opacity(pressed ? 0.6 : 0), radius: pressed ? 14 : 0)
        .scaleEffect(pressed ? 0.92 : 1)
        .animation(.spring(response: 0.18, dampingFraction: 0.7), value: pressed)
    }
}

// MARK: - ABXY

struct FaceButtonCluster: View {
    var pressed: Set<TouchControlID>
    var size: CGFloat

    var body: some View {
        let offset = size * 0.33
        let d = size * 0.38
        ZStack {
            button(.y, "Y", Theme.Palette.buttonY, d).offset(y: -offset)
            button(.x, "X", Theme.Palette.buttonX, d).offset(x: -offset)
            button(.b, "B", Theme.Palette.buttonB, d).offset(x: offset)
            button(.a, "A", Theme.Palette.buttonA, d).offset(y: offset)
        }
        .frame(width: size, height: size)
    }

    private func button(_ id: TouchControlID, _ letter: String, _ color: Color, _ d: CGFloat) -> some View {
        GlassControl(shape: Circle(), pressed: pressed.contains(id), glow: color) {
            Text(verbatim: letter)
                .font(Theme.Typography.controllerGlyph(d * 0.4))
        }
        .frame(width: d, height: d)
    }
}

// MARK: - 十字键

struct DPadVisual: View {
    var pressed: Set<TouchControlID>
    var size: CGFloat

    var body: some View {
        let arm = size * 0.36
        ZStack {
            GlassControl(shape: DPadInsettable(), pressed: false) { EmptyView() }
            // 各方向高亮
            ForEach(Array(directions.enumerated()), id: \.offset) { _, item in
                let isOn = pressed.contains(item.0)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(isOn ? 0.35 : 0))
                    .frame(width: arm * 0.9, height: arm * 0.9)
                    .offset(x: item.1.x * arm, y: item.1.y * arm)
                Image(systemName: item.2)
                    .font(.system(size: arm * 0.28, weight: .bold))
                    .foregroundStyle(Color.white.opacity(isOn ? 1 : 0.6))
                    .offset(x: item.1.x * arm * 1.02, y: item.1.y * arm * 1.02)
            }
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.18, dampingFraction: 0.7), value: pressed)
    }

    private var directions: [(TouchControlID, CGPoint, String)] {
        [
            (.dpadUp, CGPoint(x: 0, y: -1), "arrowtriangle.up.fill"),
            (.dpadDown, CGPoint(x: 0, y: 1), "arrowtriangle.down.fill"),
            (.dpadLeft, CGPoint(x: -1, y: 0), "arrowtriangle.left.fill"),
            (.dpadRight, CGPoint(x: 1, y: 0), "arrowtriangle.right.fill")
        ]
    }
}

/// 可内缩的十字形，用于 strokeBorder
struct DPadInsettable: InsettableShape {
    var inset: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        DPadShape(armWidthRatio: 0.36).path(in: rect.insetBy(dx: inset, dy: inset))
    }
    func inset(by amount: CGFloat) -> DPadInsettable {
        var copy = self
        copy.inset += amount
        return copy
    }
}

// MARK: - 摇杆

struct StickVisualView: View {
    var visual: StickVisual
    var diameter: CGFloat
    var label: String

    var body: some View {
        let knobSize = diameter * 0.42
        let magnitude = CGFloat(min(1, visual.value.magnitude))
        let angle = Angle(radians: Double(atan2(visual.knob.y, visual.knob.x)))
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().fill(Color.black.opacity(0.22))
            Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.75)
            Circle().strokeBorder(Color.white.opacity(0.06), lineWidth: 0.75).padding(diameter * 0.18)

            // 方向光弧：指示推动方向与力度
            if magnitude > 0.01 {
                Circle()
                    .trim(from: 0, to: 0.06 + 0.16 * magnitude)
                    .stroke(Theme.Palette.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(angle - .degrees(Double(360 * (0.06 + 0.16 * magnitude)) / 2))
                    .shadow(color: Theme.Palette.accent.opacity(0.9), radius: 6)
                    .padding(1.5)
            }

            // 圆钮
            ZStack {
                Circle().fill(Color.white.opacity(visual.active ? 0.85 : 0.55))
                Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 0.5)
                Text(verbatim: label)
                    .font(Theme.Typography.controllerGlyph(knobSize * 0.3))
                    .foregroundStyle(Color.black.opacity(0.55))
            }
            .frame(width: knobSize, height: knobSize)
            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
            .offset(x: visual.knob.x, y: visual.knob.y)
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - 肩键 / 扳机

struct ShoulderVisual: View {
    var label: String
    var pressed: Bool
    var size: CGSize

    var body: some View {
        GlassControl(shape: Capsule(style: .continuous), pressed: pressed) {
            Text(verbatim: label)
                .font(Theme.Typography.controllerGlyph(size.height * 0.42))
        }
        .frame(width: size.width, height: size.height)
    }
}

/// 弧形扳机：外侧顶角更圆
struct TriggerShape: InsettableShape {
    var isLeft: Bool
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let big = min(r.width, r.height) * 0.62
        let small = min(r.width, r.height) * 0.28
        var p = Path()
        let tl = isLeft ? big : small
        let tr = isLeft ? small : big
        p.move(to: CGPoint(x: r.minX + tl, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + tr), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - small))
        p.addQuadCurve(to: CGPoint(x: r.maxX - small, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + small, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - small), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + tl))
        p.addQuadCurve(to: CGPoint(x: r.minX + tl, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> TriggerShape {
        var copy = self
        copy.inset += amount
        return copy
    }
}

struct TriggerVisual: View {
    var label: String
    var isLeft: Bool
    var value: Float
    var size: CGSize

    var body: some View {
        GlassControl(shape: TriggerShape(isLeft: isLeft), pressed: value > 0) {
            ZStack(alignment: .bottom) {
                // 渐增模式下显示力度
                TriggerShape(isLeft: isLeft)
                    .fill(Color.white.opacity(0.18))
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: size.height * CGFloat(value))
                    }
                Text(verbatim: label)
                    .font(Theme.Typography.controllerGlyph(size.height * 0.34))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - View / Menu / Xbox

struct SystemButtonVisual: View {
    var kind: TouchElementKind
    var pressed: Bool
    var size: CGFloat

    var body: some View {
        GlassControl(shape: Circle(), pressed: pressed) {
            switch kind {
            case .nexus:
                NexusGlyph(lineWidth: 1.2, tint: .white)
                    .frame(width: size * 0.55, height: size * 0.55)
            case .view:
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: size * 0.34, weight: .semibold))
            default:
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: size * 0.34, weight: .semibold))
            }
        }
        .frame(width: size, height: size)
    }
}

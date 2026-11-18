import SwiftUI

/// 玻璃材质：超薄材质 + 6% 白色填充 + 0.5pt 受光渐变描边（顶部亮、底部暗）。
struct GlassBackground<S: InsettableShape>: ViewModifier {
    var shape: S
    var fill: Color = Theme.Palette.surfaceFill
    var strokeOpacity: Double = 1
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(fill)
                    // 内高光：顶部极淡的白色渐变
                    shape.fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.06), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity((contrast == .increased ? 0.45 : 0.24) * strokeOpacity),
                                Color.white.opacity((contrast == .increased ? 0.20 : 0.04) * strokeOpacity)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: contrast == .increased ? 1 : 0.5
                    )
                }
            }
    }
}

/// 卡片阴影：一层柔和的大阴影。
struct CardShadow: ViewModifier {
    var pressed: Bool = false
    func body(content: Content) -> some View {
        content.shadow(
            color: Theme.Shadow.cardColor.opacity(pressed ? 0.5 : 1),
            radius: pressed ? Theme.Shadow.cardRadius * 0.6 : Theme.Shadow.cardRadius,
            x: 0,
            y: pressed ? Theme.Shadow.cardY * 0.5 : Theme.Shadow.cardY
        )
    }
}

extension View {
    func glass(cornerRadius: CGFloat = Theme.Radius.card, fill: Color = Theme.Palette.surfaceFill) -> some View {
        modifier(GlassBackground(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), fill: fill))
    }

    func glassCapsule(fill: Color = Theme.Palette.surfaceFill) -> some View {
        modifier(GlassBackground(shape: Capsule(style: .continuous), fill: fill))
    }

    func glassCircle(fill: Color = Theme.Palette.surfaceFill) -> some View {
        modifier(GlassBackground(shape: Circle(), fill: fill))
    }

    func cardShadow(pressed: Bool = false) -> some View {
        modifier(CardShadow(pressed: pressed))
    }

    /// 发丝分隔线
    func hairlineDivider() -> some View {
        self.overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Palette.hairline).frame(height: 0.5)
        }
    }
}

/// 一条发丝线
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Palette.hairline)
            .frame(height: 0.5)
    }
}

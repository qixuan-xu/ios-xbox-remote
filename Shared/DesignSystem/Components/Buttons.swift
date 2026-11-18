import SwiftUI

/// 主按钮：高 56、全宽、强调绿填充，按下时缩小并有光晕扩散。
struct PrimaryButtonStyle: ButtonStyle {
    var isLoading: Bool = false
    var isDone: Bool = false
    var tint: Color = Theme.Palette.accent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return ZStack {
            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .bold))
                    .transition(.scale.combined(with: .opacity))
            } else if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Color.black.opacity(0.8))
                    .transition(.opacity)
            } else {
                configuration.label
                    .font(Theme.Typography.headline)
                    .transition(.opacity)
            }
        }
        .foregroundStyle(Color.black.opacity(0.86))
        .frame(maxWidth: .infinity, minHeight: 56)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(isEnabled ? 1 : 0.35), tint.opacity(isEnabled ? 0.82 : 0.3)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
                        .blendMode(.overlay)
                )
        }
        // 光晕
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .fill(tint)
                .blur(radius: pressed ? 22 : 14)
                .opacity(isEnabled ? (pressed ? 0.55 : 0.22) : 0)
                .scaleEffect(pressed ? 1.04 : 0.96)
        }
        .scaleEffect(pressed ? 0.97 : 1)
        .animation(Theme.Motion.snappy, value: pressed)
        .animation(Theme.Motion.spring, value: isLoading)
        .animation(Theme.Motion.spring, value: isDone)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
    }
}

/// 幽灵按钮：玻璃底 + 主文字色
struct GhostButtonStyle: ButtonStyle {
    var fullWidth: Bool = true
    var tint: Color = Theme.Palette.textPrimary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundStyle(tint)
            .padding(.horizontal, Theme.Spacing.l)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 50)
            .glass(cornerRadius: Theme.Radius.button,
                   fill: configuration.isPressed ? Theme.Palette.surfaceFillPressed : Theme.Palette.surfaceFill)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.Motion.snappy, value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
    }
}

/// 描边按钮
struct OutlineButtonStyle: ButtonStyle {
    var tint: Color = Theme.Palette.textPrimary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundStyle(tint)
            .padding(.horizontal, Theme.Spacing.l)
            .frame(minHeight: 46)
            .background(
                Capsule(style: .continuous)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.Motion.snappy, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// 纯文字次级按钮
struct TextButtonStyle: ButtonStyle {
    var tint: Color = Theme.Palette.textSecondary
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.callout.weight(.medium))
            .foregroundStyle(tint)
            .opacity(configuration.isPressed ? 0.5 : 1)
            .padding(.vertical, Theme.Spacing.xs)
            .contentShape(Rectangle())
    }
}

/// 圆形图标按钮（玻璃）
struct GlassIconButtonStyle: ButtonStyle {
    var size: CGFloat = 40
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(Theme.Palette.textPrimary)
            .frame(width: size, height: size)
            .glassCircle(fill: configuration.isPressed ? Theme.Palette.surfaceFillPressed : Theme.Palette.surfaceFill)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(Theme.Motion.snappy, value: configuration.isPressed)
            .contentShape(Circle())
    }
}

/// 按下缩放的卡片按钮
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.Motion.snappy, value: configuration.isPressed)
    }
}

/// 按住确认按钮（例如「断开连接」）：按住一段时间，环形进度填满后触发。
struct HoldToConfirmButton: View {
    var title: LocalizedStringKey
    var systemImage: String
    var tint: Color = Theme.Palette.danger
    var duration: Double = 0.6
    var action: () -> Void

    @State private var progress: CGFloat = 0
    @State private var isHolding = false

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ZStack {
                Circle().stroke(tint.opacity(0.25), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
            }
            .frame(width: 22, height: 22)
            Text(title)
                .font(Theme.Typography.headline)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .strokeBorder(tint.opacity(isHolding ? 0.8 : 0.4), lineWidth: 1)
        )
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .fill(tint.opacity(isHolding ? 0.12 : 0.0))
        )
        .scaleEffect(isHolding ? 0.98 : 1)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
        .onLongPressGesture(minimumDuration: duration, maximumDistance: 40, perform: {
            Haptics.success()
            action()
            progress = 0
        }, onPressingChanged: { pressing in
            isHolding = pressing
            if pressing {
                Haptics.selection()
                withAnimation(.linear(duration: duration)) { progress = 1 }
            } else {
                withAnimation(Theme.Motion.snappy) { progress = 0 }
            }
        })
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
        .accessibilityHint(Text("按住以确认"))
    }
}

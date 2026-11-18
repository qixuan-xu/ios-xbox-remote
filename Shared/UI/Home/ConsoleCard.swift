import SwiftUI

/// 主页主机卡片：主机线稿 + 状态色环境光晕 + 名称 + 状态胶囊 + 播放按钮
struct ConsoleCard: View {
    var console: Console
    var displayName: String
    var isDefault: Bool
    var isLaunching: Bool
    var heroNamespace: Namespace.ID?
    var onPlay: () -> Void

    @State private var breathe = false
    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onPlay) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    // 线稿 + 光晕
                    ZStack {
                        Ellipse()
                            .fill(console.status.color.opacity(console.status == .offline ? 0.05 : 0.22))
                            .frame(width: 200, height: 120)
                            .blur(radius: 40)
                            .scaleEffect(breathe ? 1.08 : 0.94)
                            .opacity(breathe ? 1 : 0.75)

                        if isLaunching {
                            Color.clear.frame(height: 128)
                        } else {
                            ConsoleSilhouette(kind: console.kind, lineWidth: 1.2,
                                              dimmed: console.status == .offline)
                                .frame(height: 128)
                                .hero("console-\(console.id)", in: heroNamespace)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .padding(.top, Theme.Spacing.l)

                    Spacer(minLength: Theme.Spacing.s)

                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(displayName)
                                    .titleStyle()
                                    .lineLimit(1)
                                if isDefault {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.Palette.amber)
                                        .accessibilityLabel(Text("默认主机"))
                                }
                            }
                            Text(console.kind.displayName)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.textTertiary)
                        }
                        Spacer()
                        PlayButton(enabled: console.status.canStream)
                    }
                    .padding(Theme.Spacing.l)
                }

                StatusPill(status: console.status)
                    .padding(Theme.Spacing.m)
            }
            .frame(minHeight: 236)
            .glass()
            .cardShadow(pressed: pressed)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(PressReportingStyle(pressed: $pressed))
        .onAppear {
            guard console.status == .online, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { breathe = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(displayName)，\(console.kind.displayName)"))
        .accessibilityValue(Text(console.status.label))
        .accessibilityHint(Text(console.status.canStream ? LocalizedStringKey("开始游玩") : LocalizedStringKey("主机离线")))
        .accessibilityAddTraits(.isButton)
    }
}

/// 卡片右下角的圆形播放按钮
private struct PlayButton: View {
    var enabled: Bool

    var body: some View {
        ZStack {
            if enabled {
                Circle()
                    .fill(Theme.Palette.accent)
                    .shadow(color: Theme.Palette.accent.opacity(0.45), radius: 14, y: 4)
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .offset(x: 1.5)
            } else {
                Circle().strokeBorder(Theme.Palette.textTertiary, lineWidth: 1)
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .offset(x: 1.5)
            }
        }
        .frame(width: 54, height: 54)
    }
}

/// 把按下状态暴露出来，用于联动阴影
private struct PressReportingStyle: ButtonStyle {
    @Binding var pressed: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.Motion.snappy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { pressed = $0 }
    }
}

/// 输入设备条
struct ControllerStatusStrip: View {
    @EnvironmentObject private var controllers: ControllerManager

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Group {
                if controllers.primaryController != nil {
                    ControllerGlyph(lineWidth: 1, tint: Theme.Palette.accent)
                        .frame(width: 30)
                } else {
                    #if os(iOS)
                    Image(systemName: "hand.tap")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Theme.Palette.textSecondary)
                    #else
                    Image(systemName: "keyboard")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Theme.Palette.textSecondary)
                    #endif
                }
            }
            .frame(width: 34, height: 24)
            .transition(.scale.combined(with: .opacity))

            VStack(alignment: .leading, spacing: 1) {
                if let controller = controllers.primaryController {
                    Text(controller.name)
                        .font(Theme.Typography.callout.weight(.semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                    Text(controllers.controllers.count > 1 ? LocalizedStringKey("已连接 \(controllers.controllers.count) 个手柄") : LocalizedStringKey("已连接"))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                } else {
                    #if os(iOS)
                    Text("屏幕按键")
                        .font(Theme.Typography.callout.weight(.semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("连接蓝牙手柄后自动切换")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                    #else
                    Text("键盘与鼠标")
                        .font(Theme.Typography.callout.weight(.semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("连接蓝牙手柄后自动切换")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                    #endif
                }
            }
            Spacer()
            if let controller = controllers.primaryController {
                BatteryRing(level: controller.battery)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, 10)
        .glassCapsule()
        .animation(Theme.Motion.spring, value: controllers.controllers)
        .accessibilityElement(children: .combine)
    }
}

/// 没有主机时的空状态
struct EmptyStateView: View {
    var onGuide: () -> Void
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            ConsoleSilhouette(kind: .seriesX, lineWidth: 1, tint: Theme.Palette.textTertiary, dashed: true)
                .frame(height: 110)
                .padding(.top, Theme.Spacing.l)
            Text("未找到主机")
                .titleStyle()
            Text("请确认主机已开启远程功能，并登录了同一个 Microsoft 账号。")
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Spacing.s) {
                Button("查看设置指南", action: onGuide)
                    .buttonStyle(OutlineButtonStyle())
                Button("重新查找", action: onRetry)
                    .buttonStyle(TextButtonStyle())
            }
            .padding(.bottom, Theme.Spacing.l)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .frame(maxWidth: .infinity)
        .glass()
    }
}

/// 主机详情
struct ConsoleDetailSheet: View {
    var console: Console
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState

    var body: some View {
        ZStack {
            AmbientBackground(intensity: 0.6)
            VStack(spacing: Theme.Spacing.l) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .buttonStyle(GlassIconButtonStyle(size: 34))
                }
                ConsoleSilhouette(kind: console.kind).frame(height: 120)
                Text(app.displayName(for: console)).titleStyle()
                SettingsGroup {
                    detailRow("型号", console.kind.displayName)
                    detailRow("状态", nil, status: console.status)
                    detailRow("区域", console.region ?? "—")
                    detailRow("主机 ID", String(console.id.prefix(12)) + "…", showsDivider: false)
                }
                Spacer()
            }
            .padding(Theme.Spacing.l)
        }
        .preferredColorScheme(.dark)
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
    }

    private func detailRow(_ title: LocalizedStringKey, _ value: String?, status: ConsoleStatus? = nil, showsDivider: Bool = true) -> some View {
        SettingsRow(title: title, showsDivider: showsDivider) {
            if let status {
                StatusPill(status: status)
            } else {
                Text(value ?? "")
                    .font(Theme.Typography.mono(15))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }
}

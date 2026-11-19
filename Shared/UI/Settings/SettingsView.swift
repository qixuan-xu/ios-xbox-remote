import SwiftUI

/// 设置：自定义玻璃分组卡片，与整体风格一致
struct SettingsView: View {
    var isSheet: Bool
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var controllers: ControllerManager
    @Environment(\.dismiss) private var dismiss

    @State private var showGuide = false
    @State private var confirmSignOut = false
    #if os(iOS)
    @State private var showLayoutEditor = false
    #endif

    var body: some View {
        ZStack {
            AmbientBackground(intensity: 0.6)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    header
                    accountSection
                    streamSection
                    #if os(iOS)
                    touchSection
                    #endif
                    controllerSection
                    #if os(macOS)
                    KeyMappingView()
                    #endif
                    aboutSection
                }
                .padding(Theme.Spacing.l)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            #if os(iOS)
            if DebugLaunch.is("editor") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { showLayoutEditor = true }
            }
            #endif
        }
        .sheet(isPresented: $showGuide) {
            SetupGuideView()
                #if os(macOS)
                .frame(width: 560, height: 620)
                #endif
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showLayoutEditor, onDismiss: {
            OrientationLock.set(UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown)
        }) {
            TouchLayoutEditorView()
                .environmentObject(settings)
        }
        #endif
        .confirmationDialog("退出登录？", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                dismiss()
                app.signOut()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("退出后需要重新登录才能连接主机。")
        }
    }

    private var header: some View {
        HStack {
            Text("设置").largeTitleStyle()
            Spacer()
            if isSheet {
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(GlassIconButtonStyle(size: 34))
                    .accessibilityLabel(Text("关闭"))
            }
        }
        .padding(.top, isSheet ? Theme.Spacing.s : 0)
    }

    // MARK: 账号

    private var accountSection: some View {
        SettingsGroup(title: "账号") {
            HStack(spacing: Theme.Spacing.m) {
                AvatarView(profile: app.profile, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.profile?.gamertag ?? "—")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    if let email = app.profile?.maskedEmail {
                        Text(verbatim: email)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textTertiary)
                    } else if app.isDemoMode {
                        Text("演示模式")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.amber)
                    }
                }
                Spacer()
            }
            .padding(Theme.Spacing.m)
            Hairline()
            Button {
                confirmSignOut = true
            } label: {
                SettingsRow(icon: "rectangle.portrait.and.arrow.right", title: "退出登录", showsDivider: false,
                            titleColor: Theme.Palette.danger) { EmptyView() }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 串流

    private var streamSection: some View {
        SettingsGroup(title: "串流") {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "sparkles.tv")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(width: 24)
                    Text("分辨率").font(Theme.Typography.body).foregroundStyle(Theme.Palette.textPrimary)
                }
                SegmentedPicker(options: StreamResolution.allCases.map { ($0, $0.label) }, selection: $settings.resolution)
                    .padding(.leading, 36)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 12)
            Hairline().padding(.leading, 52)

            SliderRow(icon: "speedometer", title: "码率上限", value: $settings.maxBitrateMbps, range: 0...30, step: 1,
                      format: { $0 == 0 ? String(localized: "自动") : "\(Int($0)) Mbps" })

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "aspectratio")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(width: 24)
                    Text("画面比例").font(Theme.Typography.body).foregroundStyle(Theme.Palette.textPrimary)
                }
                SegmentedPicker(options: VideoFillMode.allCases.map { ($0, $0.label) }, selection: $settings.videoFillMode)
                    .padding(.leading, 36)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 12)
            Hairline().padding(.leading, 52)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(width: 24)
                    Text("画面模式").font(Theme.Typography.body).foregroundStyle(Theme.Palette.textPrimary)
                }
                SegmentedPicker(options: VideoPacing.allCases.map { ($0, $0.label) }, selection: $settings.videoPacing)
                    .padding(.leading, 36)
                Text(settings.videoPacing.hint)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .padding(.leading, 36)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 12)
            Hairline().padding(.leading, 52)

            ToggleRow(icon: "speaker.wave.2", title: "游戏声音", isOn: $settings.audioEnabled)
            ToggleRow(icon: "chart.xyaxis.line", title: "性能浮层", subtitle: "显示延迟、帧率、码率和丢包",
                      isOn: $settings.showStats, showsDivider: false)
        }
    }

    // MARK: 屏幕按键

    #if os(iOS)
    private var touchSection: some View {
        SettingsGroup(title: "屏幕按键") {
            ToggleRow(icon: "hand.tap", title: "显示屏幕按键", subtitle: "连接蓝牙手柄时会自动隐藏",
                      isOn: $settings.showTouchControls)
            SliderRow(icon: "circle.lefthalf.filled", title: "透明度", value: $settings.controlsOpacity, range: 0.2...1,
                      format: { "\(Int($0 * 100))%" })
            SliderRow(icon: "arrow.up.left.and.arrow.down.right", title: "按键大小", value: $settings.buttonScale,
                      range: 0.7...1.4, format: { "\(Int($0 * 100))%" })
            SliderRow(icon: "scope", title: "摇杆死区", value: $settings.stickDeadzone, range: 0...0.3,
                      format: { "\(Int($0 * 100))%" })
            ToggleRow(icon: "hand.point.up.left", title: "浮动左摇杆", subtitle: "在左半屏任意位置按下即出现",
                      isOn: $settings.floatingLeftStick)
            ToggleRow(icon: "waveform", title: "按键触感", isOn: $settings.touchHaptics)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "l.joystick.press.down")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(width: 24)
                    Text("扳机模式").font(Theme.Typography.body).foregroundStyle(Theme.Palette.textPrimary)
                }
                SegmentedPicker(options: TriggerMode.allCases.map { ($0, $0.label) }, selection: $settings.triggerMode)
                    .padding(.leading, 36)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 12)
            Hairline().padding(.leading, 52)
            Button {
                showLayoutEditor = true
            } label: {
                NavigationRowLabel(icon: "square.and.pencil", title: "编辑布局",
                                   value: TouchLayoutStore.shared.current.name, showsDivider: false)
            }
            .buttonStyle(.plain)
        }
    }
    #endif

    // MARK: 手柄

    private var controllerSection: some View {
        SettingsGroup(title: "手柄") {
            if controllers.controllers.isEmpty {
                SettingsRow(icon: "gamecontroller", title: "没有已连接的手柄",
                            subtitle: "在系统设置的蓝牙里配对 Xbox、PlayStation 或 MFi 手柄") { EmptyView() }
            } else {
                ForEach(controllers.controllers) { controller in
                    HStack(spacing: Theme.Spacing.s) {
                        ControllerGlyph(lineWidth: 0.9, tint: Theme.Palette.accent)
                            .frame(width: 30)
                        Text(controller.name)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Spacer()
                        BatteryRing(level: controller.battery)
                    }
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.vertical, 12)
                    Hairline().padding(.leading, Theme.Spacing.m)
                }
            }
            SliderRow(icon: "iphone.radiowaves.left.and.right", title: "震动强度", value: $settings.controllerRumble,
                      range: 0...1, format: { $0 == 0 ? String(localized: "关闭") : "\(Int($0 * 100))%" },
                      showsDivider: false)
        }
    }

    // MARK: 关于

    private var aboutSection: some View {
        SettingsGroup(title: "关于") {
            Button { showGuide = true } label: {
                NavigationRowLabel(icon: "book", title: "设置指南")
            }
            .buttonStyle(.plain)
            SettingsRow(icon: "info.circle", title: "版本") {
                Text(verbatim: appVersion)
                    .font(Theme.Typography.mono(15))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("开源致谢")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(verbatim: "xbox-xcloud-player · xal-node · Greenlight · WebRTC")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                Text("本 App 与 Microsoft 无关，Xbox 是 Microsoft 的商标。")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 12)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

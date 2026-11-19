import SwiftUI

/// 串流覆盖层：连接中显示连接页，有画面后切到串流页
struct StreamContainer: View {
    @ObservedObject var stream: StreamController
    @State private var enteredStreamMode = false

    private var showsStream: Bool {
        switch stream.phase {
        case .streaming, .reconnecting: return true
        default: return false
        }
    }

    var body: some View {
        ZStack {
            if showsStream {
                StreamView(stream: stream)
                    .transition(.opacity)
            } else {
                ConnectingView(stream: stream)
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.spring, value: showsStream)
        .onChange(of: stream.phase) { phase in
            switch phase {
            case .connecting(.video), .streaming:
                if !enteredStreamMode { enteredStreamMode = true; PlatformHooks.enterStream() }
            default:
                break
            }
        }
        .onDisappear {
            if enteredStreamMode { PlatformHooks.exitStream() }
        }
    }
}

/// 串流页：全屏画面 + 触控层 / 键盘 + 快捷菜单 + 性能浮层
struct StreamView: View {
    @ObservedObject var stream: StreamController
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var controllers: ControllerManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var firstFrameShown = false
    @State private var localToast: ToastMessage?
    @State private var chromeVisible = true
    @State private var chromeTask: Task<Void, Never>?
    @State private var showKeyMap = false
    #if os(iOS)
    @State private var showLayoutEditor = false
    #endif

    private var usingController: Bool {
        // 截图模式下模拟器自带的虚拟手柄会让屏幕按键隐藏，这里强制显示
        if DebugLaunch.screen != nil { return false }
        return controllers.primaryController != nil
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                video
                    .scaleEffect(stream.isMenuOpen ? 0.94 : 1)
                    .brightness(stream.isMenuOpen ? -0.25 : 0)
                    .blur(radius: isReconnecting ? 14 : 0)
                    .opacity(firstFrameShown ? 1 : 0)
                    .ignoresSafeArea()

                #if os(iOS)
                TouchControlsView(
                    active: settings.showTouchControls && !usingController && !stream.isMenuOpen && !isReconnecting,
                    onMenuGesture: { toggleMenu(true) }
                )
                .opacity(settings.showTouchControls && !usingController ? 1 : 0)
                .animation(Theme.Motion.gentle, value: usingController)
                .ignoresSafeArea()
                #endif

                chrome(size: geo.size)

                #if os(macOS)
                if settings.captionsEnabled {
                    CaptionOverlay(engine: stream.captions,
                                   display: settings.captionDisplay,
                                   fontScale: settings.captionFontScale)
                        .transition(.opacity)
                }
                #endif

                if isReconnecting {
                    ReconnectOverlay(stream: stream, onLeave: { app.closeStream() })
                        .transition(.opacity)
                }

                if stream.isMenuOpen {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture { toggleMenu(false) }
                }

                HStack {
                    #if os(macOS)
                    Spacer()
                    #endif
                    if stream.isMenuOpen {
                        StreamMenuPanel(stream: stream,
                                        onDisconnect: { app.closeStream() },
                                        onEditLayout: openLayoutEditor,
                                        onClose: { toggleMenu(false) })
                            .frame(width: 320)
                            .transition(.move(edge: menuEdge).combined(with: .opacity))
                    }
                    #if os(iOS)
                    Spacer()
                    #endif
                }
                .padding(Theme.Spacing.s)

                if let dialog = stream.dialog {
                    ServerDialogView(dialog: dialog,
                                     onConfirm: { stream.answerDialog(confirm: true) },
                                     onCancel: { stream.answerDialog(confirm: false) })
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                #if os(macOS)
                if showKeyMap {
                    KeyMapOverlay(bindings: settings.keyBindings) { dismissKeyMap() }
                        .transition(.opacity)
                }
                #endif
            }
            .animation(Theme.Motion.adaptive(reduceMotion), value: stream.isMenuOpen)
            .animation(Theme.Motion.spring, value: isReconnecting)
            .animation(Theme.Motion.spring, value: stream.dialog)
        }
        .toastHost($localToast)
        #if os(iOS)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all)
        .fullScreenCover(isPresented: $showLayoutEditor) { TouchLayoutEditorView() }
        #endif
        #if os(macOS)
        .onContinuousHover { phase in
            if case .active = phase { revealChrome() }
        }
        #endif
        .onAppear {
            withAnimation(.easeIn(duration: 0.3)) { firstFrameShown = true }
            revealChrome()
            stream.updateCaptions(enabled: settings.captionsEnabled, language: settings.captionLanguage)
            #if os(macOS)
            if !settings.hasSeenKeyMapOverlay && !usingController {
                showKeyMap = true
                controllers.onAnyKeyPress = { dismissKeyMap() }
            }
            #endif
        }
        .onDisappear {
            controllers.onAnyKeyPress = nil
            chromeTask?.cancel()
        }
        .onChange(of: settings.captionsEnabled) { enabled in
            stream.updateCaptions(enabled: enabled, language: settings.captionLanguage)
        }
        .onChange(of: settings.captionLanguage) { language in
            stream.updateCaptions(enabled: settings.captionsEnabled, language: language)
        }
        .onChange(of: stream.captionError) { message in
            guard let message else { return }
            localToast = ToastMessage(icon: "captions.bubble", text: message, style: .warning,
                                      actionTitle: String(localized: "打开系统设置"), duration: 6, action: {
                #if os(macOS)
                MacActions.openPrivacySettings()
                #endif
            })
            settings.captionsEnabled = false
            stream.captionError = nil
        }
        .onChange(of: controllers.controllers.map(\.id)) { ids in
            if ids.first != nil, let first = controllers.primaryController {
                localToast = ToastMessage(icon: "gamecontroller",
                                          text: String(localized: "已切换到 \(first.name)"),
                                          style: .success, duration: 2)
            } else {
                #if os(iOS)
                localToast = ToastMessage(icon: "hand.tap", text: String(localized: "手柄已断开，已切换到屏幕按键"), duration: 2)
                #else
                localToast = ToastMessage(icon: "keyboard", text: String(localized: "手柄已断开，已切换到键盘"), duration: 2)
                #endif
            }
        }
    }

    private var isReconnecting: Bool {
        if case .reconnecting = stream.phase { return true }
        return false
    }

    private var menuEdge: Edge {
        #if os(macOS)
        return .trailing
        #else
        return .leading
        #endif
    }

    @ViewBuilder
    private var video: some View {
        if stream.isDemo {
            DemoVideoView()
                .aspectRatio(16 / 9, contentMode: settings.videoFillMode == .fill ? .fill : .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            VideoView(frameTap: stream.frameTap, fillMode: settings.videoFillMode, pacing: settings.videoPacing)
        }
    }

    // MARK: 顶部浮动元素

    @ViewBuilder
    private func chrome(size: CGSize) -> some View {
        VStack {
            HStack(alignment: .top) {
                #if os(iOS)
                menuDot
                #endif
                Spacer()
                if settings.showStats {
                    StatsOverlay(stats: stream.stats)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                #if os(macOS)
                Button { toggleMenu(!stream.isMenuOpen) } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(GlassIconButtonStyle(size: 36))
                .opacity(chromeVisible ? 1 : 0)
                .help(Text("快捷菜单 (⌃⌘M)"))
                #endif
            }
            Spacer()
            #if os(macOS)
            HStack {
                InputSourcePill()
                    .opacity(chromeVisible ? 1 : 0.0)
                Spacer()
            }
            #endif
        }
        .padding(Theme.Spacing.m)
        .animation(Theme.Motion.gentle, value: chromeVisible)
        .animation(Theme.Motion.spring, value: settings.showStats)
    }

    #if os(iOS)
    private var menuDot: some View {
        Button { toggleMenu(true) } label: {
            Circle()
                .fill(Color.white.opacity(0.85))
                .frame(width: 6, height: 6)
                .frame(width: 30, height: 30)
                .glassCircle()
                .opacity(chromeVisible ? 0.9 : 0.18)
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(Text("快捷菜单"))
    }
    #endif

    private func toggleMenu(_ open: Bool) {
        Haptics.selection()
        stream.isMenuOpen = open
        if !open { revealChrome() }
    }

    /// 显示浮动元素，4 秒（Mac 2 秒）无操作后淡出
    private func revealChrome() {
        chromeVisible = true
        chromeTask?.cancel()
        #if os(macOS)
        let delay: UInt64 = 2_000_000_000
        #else
        let delay: UInt64 = 4_000_000_000
        #endif
        chromeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            chromeVisible = false
            #if os(macOS)
            if !stream.isMenuOpen { PlatformHooks.scheduleCursorHide() }
            #endif
        }
    }

    private func openLayoutEditor() {
        #if os(iOS)
        stream.isMenuOpen = false
        showLayoutEditor = true
        #endif
    }

    private func dismissKeyMap() {
        guard showKeyMap else { return }
        showKeyMap = false
        settings.hasSeenKeyMapOverlay = true
        controllers.onAnyKeyPress = nil
    }
}

// MARK: - 性能浮层

struct StatsOverlay: View {
    var stats: StreamStats

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            item(label: "延迟", value: stats.latencyMs.map { String(format: "%.0f ms", $0) } ?? "—", color: latencyColor)
            divider
            item(label: "帧率", value: String(format: "%.0f", stats.fps), color: Theme.Palette.textPrimary)
            divider
            item(label: "码率", value: String(format: "%.1f Mb", stats.bitrateMbps), color: Theme.Palette.textPrimary)
            divider
            item(label: "丢包", value: String(format: "%.1f%%", stats.packetLossPercent),
                 color: stats.packetLossPercent > 2 ? Theme.Palette.amber : Theme.Palette.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassCapsule()
        .accessibilityElement(children: .combine)
    }

    private var latencyColor: Color {
        guard let l = stats.latencyMs else { return Theme.Palette.textPrimary }
        if l < 40 { return Theme.Palette.accent }
        if l < 90 { return Theme.Palette.amber }
        return Theme.Palette.danger
    }

    private var divider: some View {
        Rectangle().fill(Theme.Palette.hairlineStrong).frame(width: 0.5, height: 12)
    }

    private func item(label: LocalizedStringKey, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
            Text(verbatim: value)
                .font(Theme.Typography.mono(12, weight: .semibold))
                .foregroundStyle(color)
        }
    }
}

// MARK: - 断线覆盖层

struct ReconnectOverlay: View {
    @ObservedObject var stream: StreamController
    var onLeave: () -> Void

    private var seconds: Int {
        if case .reconnecting(let s) = stream.phase { return s }
        return 0
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: Theme.Spacing.m) {
                ThinRingSpinner(size: 34, lineWidth: 2)
                Text("连接中断，正在重新连接")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(verbatim: "\(seconds)s")
                    .font(Theme.Typography.mono(15))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .contentTransition(.numericText())
                    .animation(Theme.Motion.snappy, value: seconds)
                Button("返回主页", action: onLeave)
                    .buttonStyle(TextButtonStyle())
            }
            .padding(Theme.Spacing.xl)
            .glass()
        }
    }
}

// MARK: - 服务器对话框

struct ServerDialogView: View {
    var dialog: ServerDialog
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                if !dialog.title.isEmpty {
                    Text(verbatim: dialog.title).titleStyle()
                }
                Text(verbatim: dialog.message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Theme.Spacing.s) {
                    if let cancel = dialog.cancelButton {
                        Button(cancel, action: onCancel).buttonStyle(GhostButtonStyle())
                    }
                    Button(dialog.defaultButton, action: onConfirm).buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: 420)
            .glass()
            .cardShadow()
            .padding(Theme.Spacing.l)
        }
    }
}

// MARK: - 演示画面（演示模式下代替真实视频）

struct DemoVideoView: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let w = size.width, h = size.height
                let horizon = h * 0.55
                // 天空
                ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: horizon)),
                         with: .linearGradient(Gradient(colors: [Color(hex: 0x05070C), Color(hex: 0x0F2A1C)]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))
                // 太阳
                let sun = CGRect(x: w * 0.5 - h * 0.16, y: horizon - h * 0.26, width: h * 0.32, height: h * 0.32)
                ctx.fill(Path(ellipseIn: sun), with: .radialGradient(
                    Gradient(colors: [Theme.Palette.accent.opacity(0.9), Theme.Palette.accentDeep.opacity(0.0)]),
                    center: CGPoint(x: sun.midX, y: sun.midY), startRadius: 0, endRadius: h * 0.2))
                // 地面
                ctx.fill(Path(CGRect(x: 0, y: horizon, width: w, height: h - horizon)), with: .color(Color(hex: 0x030405)))
                // 透视网格
                let speed = t.truncatingRemainder(dividingBy: 1.0)
                for i in 0..<14 {
                    let z = (Double(i) + speed) / 14
                    let y = horizon + (h - horizon) * CGFloat(z * z)
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: w, y: y))
                    ctx.stroke(line, with: .color(Theme.Palette.accent.opacity(0.08 + 0.35 * z)), lineWidth: 1)
                }
                for i in -10...10 {
                    var line = Path()
                    line.move(to: CGPoint(x: w / 2 + CGFloat(i) * w * 0.02, y: horizon))
                    line.addLine(to: CGPoint(x: w / 2 + CGFloat(i) * w * 0.25, y: h))
                    ctx.stroke(line, with: .color(Theme.Palette.accent.opacity(0.18)), lineWidth: 1)
                }
            }
        }
        .accessibilityLabel(Text("演示画面"))
    }
}

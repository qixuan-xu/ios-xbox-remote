import SwiftUI

/// 串流快捷菜单：从侧边滑出的玻璃面板
struct StreamMenuPanel: View {
    @ObservedObject var stream: StreamController
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var controllers: ControllerManager
    var onDisconnect: () -> Void
    var onEditLayout: () -> Void
    var onClose: () -> Void

    #if os(iOS)
    @ObservedObject private var layouts = TouchLayoutStore.shared
    #endif
    @State private var screenshotDone = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(Theme.Spacing.m)
            Hairline()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    section("画面") {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            label("画质")
                            SegmentedPicker(options: StreamResolution.allCases.map { ($0, $0.label) },
                                            selection: $settings.resolution)
                            label("画面比例")
                            SegmentedPicker(options: VideoFillMode.allCases.map { ($0, $0.label) },
                                            selection: $settings.videoFillMode)
                            Text("画质在下次连接时生效")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }

                    #if os(iOS)
                    section("控制") {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            compactToggle("屏幕按键", isOn: $settings.showTouchControls)
                            HStack {
                                label("透明度")
                                Spacer()
                                Text(verbatim: "\(Int(settings.controlsOpacity * 100))%")
                                    .font(Theme.Typography.mono(13))
                                    .foregroundStyle(Theme.Palette.textSecondary)
                            }
                            Slider(value: $settings.controlsOpacity, in: 0.2...1)
                                .tint(Theme.Palette.accent)
                            label("布局方案")
                            Menu {
                                ForEach(layouts.schemes) { scheme in
                                    Button {
                                        layouts.select(scheme.id)
                                    } label: {
                                        if scheme.id == layouts.currentId {
                                            Label(scheme.name, systemImage: "checkmark")
                                        } else {
                                            Text(scheme.name)
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(layouts.current.name)
                                        .font(Theme.Typography.callout.weight(.medium))
                                        .foregroundStyle(Theme.Palette.textPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.Palette.textTertiary)
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 38)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.25)))
                            }
                            Button {
                                onEditLayout()
                            } label: {
                                Label("编辑布局", systemImage: "square.and.pencil")
                                    .font(Theme.Typography.callout.weight(.medium))
                            }
                            .buttonStyle(GhostButtonStyle())
                        }
                    }
                    #else
                    section("控制") {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            HStack {
                                label("当前输入")
                                Spacer()
                                Text(controllers.primaryController?.name ?? String(localized: "键盘与鼠标"))
                                    .font(Theme.Typography.callout)
                                    .foregroundStyle(Theme.Palette.textSecondary)
                            }
                            Button {
                                MacActions.openSettings()
                            } label: {
                                Label("键位映射", systemImage: "keyboard")
                                    .font(Theme.Typography.callout.weight(.medium))
                            }
                            .buttonStyle(GhostButtonStyle())
                        }
                    }
                    #endif

                    section("音频") {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            HStack(spacing: Theme.Spacing.s) {
                                Button {
                                    stream.isMuted.toggle()
                                    Haptics.selection()
                                } label: {
                                    Image(systemName: stream.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                        .frame(width: 22)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(stream.isMuted ? Theme.Palette.textTertiary : Theme.Palette.textPrimary)
                                .accessibilityLabel(Text(stream.isMuted ? LocalizedStringKey("取消静音") : LocalizedStringKey("静音")))
                                Slider(value: $stream.volume, in: 0...1)
                                    .tint(Theme.Palette.accent)
                                    .disabled(stream.isMuted)
                            }
                        }
                    }

                    section("工具") {
                        VStack(spacing: Theme.Spacing.s) {
                            compactToggle("性能浮层", isOn: $settings.showStats)
                            Button {
                                takeScreenshot()
                            } label: {
                                Label(screenshotDone ? LocalizedStringKey("已保存") : LocalizedStringKey("截图"),
                                      systemImage: screenshotDone ? "checkmark" : "camera")
                                    .font(Theme.Typography.callout.weight(.medium))
                            }
                            .buttonStyle(GhostButtonStyle())
                            #if DEBUG
                            if stream.isDemo {
                                Button("模拟断线") { onClose(); stream.simulateDisconnect() }
                                    .buttonStyle(TextButtonStyle())
                            }
                            #endif
                        }
                    }
                }
                .padding(Theme.Spacing.m)
            }

            Hairline()
            HoldToConfirmButton(title: "断开连接", systemImage: "power", action: onDisconnect)
                .padding(Theme.Spacing.m)
        }
        .frame(maxHeight: .infinity)
        .glass(cornerRadius: 26)
        .cardShadow()
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.s) {
            ConsoleSilhouette(kind: stream.console.kind, lineWidth: 0.9)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(stream.console.name)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    SignalBars(quality: stream.stats.quality)
                    Text(verbatim: stream.stats.latencyMs.map { String(format: "%.0f ms", $0) } ?? "— ms")
                        .font(Theme.Typography.mono(12))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            Spacer()
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(GlassIconButtonStyle(size: 32))
                .accessibilityLabel(Text("关闭菜单"))
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title).overlineStyle()
            content()
        }
    }

    private func label(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(Theme.Typography.callout)
            .foregroundStyle(Theme.Palette.textSecondary)
    }

    private func compactToggle(_ title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Palette.textPrimary)
        }
        .tint(Theme.Palette.accent)
    }

    private func takeScreenshot() {
        Task {
            let ok: Bool
            if stream.isDemo {
                ok = false
            } else if let frame = stream.frameTap?.snapshotFrame(), let image = FrameSnapshot.cgImage(from: frame) {
                ok = await ScreenshotSaver.save(image)
            } else {
                ok = false
            }
            if ok {
                Haptics.success()
                withAnimation(Theme.Motion.spring) { screenshotDone = true }
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                withAnimation(Theme.Motion.spring) { screenshotDone = false }
            } else {
                Haptics.warning()
            }
        }
    }
}

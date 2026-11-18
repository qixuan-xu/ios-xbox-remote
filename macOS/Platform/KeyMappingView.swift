import SwiftUI

/// Mac 键位映射：左侧手柄线稿（高亮当前分组），右侧映射表。点击某一行后按下键盘或鼠标即可绑定。
struct KeyMappingView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var controllers: ControllerManager
    @EnvironmentObject private var app: AppState
    @State private var listening: GamepadControl?
    @State private var hovered: GamepadControl?

    var body: some View {
        SettingsGroup(title: "键位映射") {
            HStack(alignment: .top, spacing: Theme.Spacing.l) {
                VStack(spacing: Theme.Spacing.m) {
                    ControllerGlyph(lineWidth: 1.2, highlight: highlightPart)
                        .frame(width: 170)
                        .animation(Theme.Motion.spring, value: highlightPart)
                    Button("恢复默认") {
                        settings.resetKeyBindings()
                        Haptics.success()
                    }
                    .buttonStyle(TextButtonStyle())
                }
                .padding(.top, Theme.Spacing.l)

                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    ForEach(GamepadControl.Group.allCases, id: \.self) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: group.title).overlineStyle()
                            ForEach(GamepadControl.allCases.filter { $0.group == group }) { control in
                                row(control)
                            }
                        }
                    }
                }
            }
            .padding(Theme.Spacing.m)
        }
        .onDisappear {
            controllers.captureNextInput = nil
            listening = nil
            KeyEventGate.swallow = app.stream != nil
        }
    }

    private func row(_ control: GamepadControl) -> some View {
        let isListening = listening == control
        return Button {
            startListening(control)
        } label: {
            HStack {
                Text(verbatim: control.displayName)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                if isListening {
                    Text("请按下按键")
                        .font(Theme.Typography.captionStrong)
                        .foregroundStyle(Theme.Palette.accent)
                        .transition(.opacity)
                } else {
                    HStack(spacing: 4) {
                        ForEach(settings.keyBindings.inputs(for: control), id: \.self) { input in
                            KeyCap(text: input.displayName)
                        }
                        if settings.keyBindings.inputs(for: control).isEmpty {
                            Text(verbatim: "—").foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isListening ? Theme.Palette.accent.opacity(0.14) : (hovered == control ? Color.white.opacity(0.05) : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isListening ? Theme.Palette.accent.opacity(0.6) : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? control : (hovered == control ? nil : hovered) }
        .animation(Theme.Motion.snappy, value: isListening)
    }

    private var highlightPart: ControllerGlyph.ControllerPart? {
        guard let control = listening ?? hovered else { return nil }
        switch control.group {
        case .sticks:
            switch control {
            case .rightStickUp, .rightStickDown, .rightStickLeft, .rightStickRight, .rightThumb: return .rightStick
            default: return .leftStick
            }
        case .face: return .faceButtons
        case .shoulders: return .shoulders
        case .dpad: return .dpad
        case .system: return control == .nexus ? .nexus : .menuButtons
        }
    }

    private func startListening(_ control: GamepadControl) {
        if listening == control {
            listening = nil
            controllers.captureNextInput = nil
            KeyEventGate.swallow = false
            return
        }
        PlatformHooks.installKeyMonitorIfNeeded()
        KeyEventGate.swallow = true
        listening = control
        controllers.captureNextInput = { input in
            KeyEventGate.swallow = app.stream != nil
            var bindings = settings.keyBindings
            let swapped = bindings.bind(input, to: control)
            settings.keyBindings = bindings
            listening = nil
            if let swapped {
                app.showToast(String(localized: "\(input.displayName) 原来绑定的是「\(swapped.displayName)」，已互换"),
                              icon: "arrow.left.arrow.right", style: .warning)
            }
        }
    }
}

struct KeyCap: View {
    var text: String
    var body: some View {
        Text(verbatim: text)
            .font(Theme.Typography.mono(12, weight: .semibold))
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.horizontal, 7)
            .frame(minWidth: 24, minHeight: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 0, y: 1)
            )
    }
}

/// 首次串流时显示的键位图浮层，按任意键关闭
struct KeyMapOverlay: View {
    var bindings: KeyBindings
    var onDismiss: () -> Void

    private let featured: [GamepadControl] = [
        .leftStickUp, .rightStickUp, .a, .b, .x, .y,
        .leftShoulder, .rightShoulder, .leftTrigger, .rightTrigger, .view, .menu, .nexus
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { onDismiss() }
            VStack(spacing: Theme.Spacing.l) {
                Text("键盘操作").titleStyle()
                HStack(alignment: .center, spacing: Theme.Spacing.xl) {
                    ControllerGlyph(lineWidth: 1.3)
                        .frame(width: 220)
                    VStack(alignment: .leading, spacing: 7) {
                        mapRow(String(localized: "左摇杆"), "W A S D")
                        mapRow(String(localized: "右摇杆"), "\u{2191} \u{2190} \u{2193} \u{2192}")
                        ForEach(featured.filter { $0 != .leftStickUp && $0 != .rightStickUp }) { control in
                            mapRow(control.displayName,
                                   bindings.inputs(for: control).map(\.displayName).joined(separator: " / "))
                        }
                    }
                }
                Text("按任意键开始")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            .padding(Theme.Spacing.xl)
            .glass()
            .cardShadow()
        }
    }

    private func mapRow(_ name: String, _ keys: String) -> some View {
        HStack {
            Text(verbatim: name)
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: 110, alignment: .leading)
            KeyCap(text: keys.isEmpty ? "—" : keys)
        }
    }
}

/// 左下角小胶囊：当前输入方式
struct InputSourcePill: View {
    @EnvironmentObject private var controllers: ControllerManager

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: controllers.primaryController == nil ? "keyboard" : "gamecontroller")
                .font(.system(size: 11, weight: .semibold))
            Text(verbatim: controllers.primaryController?.name ?? String(localized: "键盘"))
                .font(Theme.Typography.captionStrong)
        }
        .foregroundStyle(Theme.Palette.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassCapsule()
    }
}

/// 菜单栏命令
struct AppCommands: Commands {
    @ObservedObject var appState: AppState

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("刷新主机") {
                Task { await appState.refreshConsoles() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(appState.phase != .signedIn)
        }
        CommandGroup(after: .toolbar) {
            Button("全屏") { PlatformHooks.toggleFullScreen() }
                .keyboardShortcut("f", modifiers: .command)
            Button("性能浮层") { appState.settings.showStats.toggle() }
                .keyboardShortcut("i", modifiers: .command)
        }
        CommandMenu("串流") {
            Button("快捷菜单") { appState.stream?.isMenuOpen.toggle() }
                .keyboardShortcut("m", modifiers: [.control, .command])
                .disabled(appState.stream == nil)
            Button("断开连接") { appState.closeStream() }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(appState.stream == nil)
        }
    }
}

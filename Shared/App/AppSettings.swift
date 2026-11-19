import SwiftUI

/// 用户设置，持久化到 UserDefaults
@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    // 串流
    @Published var resolution: StreamResolution { didSet { save(resolution.rawValue, "resolution") } }
    /// 0 表示自动
    @Published var maxBitrateMbps: Double { didSet { save(maxBitrateMbps, "maxBitrateMbps") } }
    @Published var videoFillMode: VideoFillMode { didSet { save(videoFillMode.rawValue, "videoFillMode") } }
    @Published var videoPacing: VideoPacing { didSet { save(videoPacing.rawValue, "videoPacing") } }
    @Published var audioEnabled: Bool { didSet { save(audioEnabled, "audioEnabled") } }
    @Published var showStats: Bool { didSet { save(showStats, "showStats") } }

    // 屏幕按键
    @Published var showTouchControls: Bool { didSet { save(showTouchControls, "showTouchControls") } }
    @Published var controlsOpacity: Double { didSet { save(controlsOpacity, "controlsOpacity") } }
    @Published var buttonScale: Double { didSet { save(buttonScale, "buttonScale") } }
    @Published var touchHaptics: Bool { didSet { save(touchHaptics, "touchHaptics"); Haptics.controlsEnabled = touchHaptics } }
    @Published var stickDeadzone: Double { didSet { save(stickDeadzone, "stickDeadzone") } }
    @Published var floatingLeftStick: Bool { didSet { save(floatingLeftStick, "floatingLeftStick") } }
    @Published var triggerMode: TriggerMode { didSet { save(triggerMode.rawValue, "triggerMode") } }

    // 手柄 / 键盘
    @Published var controllerRumble: Double { didSet { save(controllerRumble, "controllerRumble") } }
    @Published var keyBindings: KeyBindings {
        didSet {
            if let data = try? JSONEncoder().encode(keyBindings) { defaults.set(data, forKey: "keyBindings") }
            ControllerManager.shared.keyBindings = keyBindings
        }
    }
    @Published var hasSeenKeyMapOverlay: Bool { didSet { save(hasSeenKeyMapOverlay, "hasSeenKeyMapOverlay") } }

    // 主机
    @Published var customConsoleNames: [String: String] { didSet { save(customConsoleNames, "customConsoleNames") } }
    @Published var defaultConsoleId: String? { didSet { save(defaultConsoleId, "defaultConsoleId") } }

    init() {
        let d = UserDefaults.standard
        resolution = StreamResolution(rawValue: d.string(forKey: "resolution") ?? "") ?? .auto
        maxBitrateMbps = d.object(forKey: "maxBitrateMbps") as? Double ?? 0
        videoFillMode = VideoFillMode(rawValue: d.string(forKey: "videoFillMode") ?? "") ?? .fit
        videoPacing = VideoPacing(rawValue: d.string(forKey: "videoPacing") ?? "") ?? .balanced
        audioEnabled = d.object(forKey: "audioEnabled") as? Bool ?? true
        showStats = d.object(forKey: "showStats") as? Bool ?? false
        showTouchControls = d.object(forKey: "showTouchControls") as? Bool ?? true
        controlsOpacity = d.object(forKey: "controlsOpacity") as? Double ?? 0.55
        buttonScale = d.object(forKey: "buttonScale") as? Double ?? 1.0
        let haptics = d.object(forKey: "touchHaptics") as? Bool ?? true
        touchHaptics = haptics
        stickDeadzone = d.object(forKey: "stickDeadzone") as? Double ?? 0.08
        floatingLeftStick = d.object(forKey: "floatingLeftStick") as? Bool ?? true
        triggerMode = TriggerMode(rawValue: d.string(forKey: "triggerMode") ?? "") ?? .instant
        controllerRumble = d.object(forKey: "controllerRumble") as? Double ?? 1.0
        let bindings = (d.data(forKey: "keyBindings")).flatMap { try? JSONDecoder().decode(KeyBindings.self, from: $0) } ?? .default
        keyBindings = bindings
        hasSeenKeyMapOverlay = d.bool(forKey: "hasSeenKeyMapOverlay")
        customConsoleNames = d.dictionary(forKey: "customConsoleNames") as? [String: String] ?? [:]
        defaultConsoleId = d.string(forKey: "defaultConsoleId")

        Haptics.controlsEnabled = haptics
        ControllerManager.shared.keyBindings = bindings
        ControllerManager.shared.rumbleIntensity = Float(controllerRumble)
    }

    func resetKeyBindings() { keyBindings = .default }

    private func save(_ value: Any?, _ key: String) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}

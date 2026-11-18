import Foundation
import GameController
import CoreHaptics
import Combine

/// 已连接的蓝牙/有线手柄
struct ConnectedController: Identifiable, Equatable {
    var id: String
    var name: String
    var battery: Float?
    var isCharging: Bool
}

/// 管理 GameController：手柄连接/断开、电量、输入读取、震动；Mac 上还读取键盘和鼠标。
/// 只在主线程使用（通知与回调都在主队列上）。
final class ControllerManager: ObservableObject {
    static let shared = ControllerManager()

    @Published private(set) var controllers: [ConnectedController] = []
    @Published private(set) var keyboardConnected = false
    /// 最近一次有输入的来源（用于界面显示当前输入方式）
    @Published private(set) var lastActiveSource: InputSourceID = .touch

    /// 只有在串流时才把键盘输入写进 InputHub
    var keyboardInputEnabled = false {
        didSet { if !keyboardInputEnabled { InputHub.shared.remove(.keyboard); pressedInputs.removeAll() } }
    }
    var keyBindings: KeyBindings = .default
    var rumbleIntensity: Float = 1

    /// 键位映射页：下一次按键回调（返回后清空）
    var captureNextInput: ((KeyInput) -> Void)?
    /// 任意键按下的回调（用于关闭首次键位图浮层）
    var onAnyKeyPress: (() -> Void)?

    private var pressedInputs = Set<KeyInput>()
    private var rumblers: [String: RumblePlayer] = [:]
    private var observers: [NSObjectProtocol] = []
    private var batteryTimer: Timer?

    var primaryController: ConnectedController? { controllers.first }

    private init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let controller = note.object as? GCController else { return }
            Task { @MainActor in self?.attach(controller) }
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
            guard let controller = note.object as? GCController else { return }
            Task { @MainActor in self?.detach(controller) }
        })
        observers.append(center.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let keyboard = note.object as? GCKeyboard else { return }
            Task { @MainActor in self?.attachKeyboard(keyboard) }
        })
        observers.append(center.addObserver(forName: .GCKeyboardDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.keyboardConnected = false }
        })
        observers.append(center.addObserver(forName: .GCMouseDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let mouse = note.object as? GCMouse else { return }
            Task { @MainActor in self?.attachMouse(mouse) }
        })

        GCController.shouldMonitorBackgroundEvents = false
        GCController.startWirelessControllerDiscovery(completionHandler: nil)

        for controller in GCController.controllers() { attach(controller) }
        if let keyboard = GCKeyboard.coalesced { attachKeyboard(keyboard) }
        if let mouse = GCMouse.current { attachMouse(mouse) }

        batteryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshBattery() }
        }
    }

    // MARK: 手柄

    private func identifier(for controller: GCController) -> String {
        String(UInt(bitPattern: ObjectIdentifier(controller).hashValue))
    }

    private func attach(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        let id = identifier(for: controller)
        guard !controllers.contains(where: { $0.id == id }) else { return }

        // 让 Xbox 键交给游戏，而不是被系统拦截
        if #available(iOS 14.0, macOS 11.0, *) {
            pad.buttonHome?.preferredSystemGestureState = .disabled
            pad.buttonOptions?.preferredSystemGestureState = .disabled
            pad.buttonMenu.preferredSystemGestureState = .disabled
        }

        pad.valueChangedHandler = { [weak self] gamepad, _ in
            let state = ControllerManager.readState(gamepad)
            InputHub.shared.update(.controller(id), state)
            if !state.isNeutral {
                Task { @MainActor in
                    if self?.lastActiveSource != .controller(id) { self?.lastActiveSource = .controller(id) }
                }
            }
        }

        controllers.append(ConnectedController(
            id: id,
            name: controller.vendorName ?? String(localized: "游戏手柄"),
            battery: controller.battery.map { $0.batteryLevel },
            isCharging: controller.battery?.batteryState == .charging
        ))
        if let haptics = controller.haptics {
            rumblers[id] = RumblePlayer(engineFactory: { haptics.createEngine(withLocality: .default) })
        }
        lastActiveSource = .controller(id)
        reassignPlayers()
    }

    /// 按连接顺序给手柄分配玩家序号（1P、2P...），同时点亮手柄上的玩家指示灯
    private func reassignPlayers() {
        let all = GCController.controllers()
        for (i, item) in controllers.enumerated() {
            let index = UInt8(min(i, 3))
            InputHub.shared.setPlayerIndex(index, for: .controller(item.id))
            if let c = all.first(where: { identifier(for: $0) == item.id }) {
                c.playerIndex = GCControllerPlayerIndex(rawValue: Int(index)) ?? .indexUnset
            }
        }
    }

    private func detach(_ controller: GCController) {
        let id = identifier(for: controller)
        controller.extendedGamepad?.valueChangedHandler = nil
        InputHub.shared.remove(.controller(id))
        controllers.removeAll { $0.id == id }
        rumblers[id]?.stop()
        rumblers.removeValue(forKey: id)
        InputHub.shared.clearPlayerIndex(for: .controller(id))
        reassignPlayers()
        if controllers.isEmpty { lastActiveSource = keyboardInputEnabled ? .keyboard : .touch }
    }

    private func refreshBattery() {
        let all = GCController.controllers()
        controllers = controllers.map { item in
            var copy = item
            if let c = all.first(where: { identifier(for: $0) == item.id }) {
                copy.battery = c.battery.map { $0.batteryLevel }
                copy.isCharging = c.battery?.batteryState == .charging
            }
            return copy
        }
    }

    static func readState(_ pad: GCExtendedGamepad) -> GamepadState {
        var s = GamepadState()
        if pad.buttonA.isPressed { s.buttons.insert(.a) }
        if pad.buttonB.isPressed { s.buttons.insert(.b) }
        if pad.buttonX.isPressed { s.buttons.insert(.x) }
        if pad.buttonY.isPressed { s.buttons.insert(.y) }
        if pad.leftShoulder.isPressed { s.buttons.insert(.leftShoulder) }
        if pad.rightShoulder.isPressed { s.buttons.insert(.rightShoulder) }
        if pad.dpad.up.isPressed { s.buttons.insert(.dpadUp) }
        if pad.dpad.down.isPressed { s.buttons.insert(.dpadDown) }
        if pad.dpad.left.isPressed { s.buttons.insert(.dpadLeft) }
        if pad.dpad.right.isPressed { s.buttons.insert(.dpadRight) }
        if pad.buttonMenu.isPressed { s.buttons.insert(.menu) }
        if pad.buttonOptions?.isPressed == true { s.buttons.insert(.view) }
        if pad.buttonHome?.isPressed == true { s.buttons.insert(.nexus) }
        if pad.leftThumbstickButton?.isPressed == true { s.buttons.insert(.leftThumb) }
        if pad.rightThumbstickButton?.isPressed == true { s.buttons.insert(.rightThumb) }
        s.leftStick = StickValue(x: pad.leftThumbstick.xAxis.value, y: pad.leftThumbstick.yAxis.value)
        s.rightStick = StickValue(x: pad.rightThumbstick.xAxis.value, y: pad.rightThumbstick.yAxis.value)
        s.leftTrigger = pad.leftTrigger.value
        s.rightTrigger = pad.rightTrigger.value
        return s
    }

    // MARK: 震动

    func rumble(_ report: VibrationReport) {
        let strength = max(report.leftMotor, report.rightMotor, report.leftTriggerMotor, report.rightTriggerMotor) * rumbleIntensity
        let sharpness = report.rightMotor > report.leftMotor ? Float(0.7) : Float(0.3)
        let duration = Double(report.durationMs) / 1000
        let target = controllers.indices.contains(Int(report.gamepadIndex)) ? controllers[Int(report.gamepadIndex)] : controllers.first
        if let target, let rumbler = rumblers[target.id] {
            rumbler.play(intensity: strength, sharpness: sharpness, duration: duration)
        } else {
            DeviceRumble.shared.play(intensity: strength, sharpness: sharpness, duration: duration)
        }
    }

    // MARK: 键盘 / 鼠标

    private func attachKeyboard(_ keyboard: GCKeyboard) {
        keyboardConnected = true
        keyboard.keyboardInput?.keyChangedHandler = { [weak self] _, _, keyCode, pressed in
            guard let name = KeyCodeNames.name(for: keyCode) else { return }
            Task { @MainActor in self?.handle(.key(name), pressed: pressed) }
        }
    }

    private func attachMouse(_ mouse: GCMouse) {
        mouse.mouseInput?.leftButton.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in self?.handle(.mouseLeft, pressed: pressed) }
        }
        mouse.mouseInput?.rightButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in self?.handle(.mouseRight, pressed: pressed) }
        }
    }

    private func handle(_ input: KeyInput, pressed: Bool) {
        if pressed {
            if let capture = captureNextInput {
                captureNextInput = nil
                capture(input)
                return
            }
            onAnyKeyPress?()
        }
        guard keyboardInputEnabled else { return }
        if pressed { pressedInputs.insert(input) } else { pressedInputs.remove(input) }
        let state = KeyboardMapper.state(pressed: pressedInputs, bindings: keyBindings)
        InputHub.shared.update(.keyboard, state)
        if pressed, lastActiveSource != .keyboard { lastActiveSource = .keyboard }
    }
}

/// GCKeyCode 与可保存的名字之间的转换
enum KeyCodeNames {
    static let table: [(String, GCKeyCode)] = {
        var t: [(String, GCKeyCode)] = [
            ("a", .keyA), ("b", .keyB), ("c", .keyC), ("d", .keyD), ("e", .keyE), ("f", .keyF),
            ("g", .keyG), ("h", .keyH), ("i", .keyI), ("j", .keyJ), ("k", .keyK), ("l", .keyL),
            ("m", .keyM), ("n", .keyN), ("o", .keyO), ("p", .keyP), ("q", .keyQ), ("r", .keyR),
            ("s", .keyS), ("t", .keyT), ("u", .keyU), ("v", .keyV), ("w", .keyW), ("x", .keyX),
            ("y", .keyY), ("z", .keyZ),
            ("1", .one), ("2", .two), ("3", .three), ("4", .four), ("5", .five),
            ("6", .six), ("7", .seven), ("8", .eight), ("9", .nine), ("0", .zero),
            ("space", .spacebar), ("escape", .escape), ("return", .returnOrEnter), ("tab", .tab),
            ("backspace", .deleteOrBackspace), ("leftShift", .leftShift), ("rightShift", .rightShift),
            ("leftControl", .leftControl), ("leftOption", .leftAlt), ("leftCommand", .leftGUI),
            ("up", .upArrow), ("down", .downArrow), ("left", .leftArrow), ("right", .rightArrow),
            ("grave", .graveAccentAndTilde), ("minus", .hyphen), ("equals", .equalSign),
            ("comma", .comma), ("period", .period), ("slash", .slash), ("semicolon", .semicolon),
            ("quote", .quote), ("leftBracket", .openBracket), ("rightBracket", .closeBracket),
            ("backslash", .backslash)
        ]
        let functionKeys: [GCKeyCode] = [.F1, .F2, .F3, .F4, .F5, .F6, .F7, .F8, .F9, .F10, .F11, .F12]
        for (i, code) in functionKeys.enumerated() { t.append(("F\(i + 1)", code)) }
        return t
    }()

    static func name(for code: GCKeyCode) -> String? {
        table.first { $0.1 == code }?.0
    }
}

/// 基于 CoreHaptics 的震动播放器（手柄或设备本身）
final class RumblePlayer {
    private let engineFactory: () -> CHHapticEngine?
    private var engine: CHHapticEngine?
    private var player: CHHapticPatternPlayer?

    init(engineFactory: @escaping () -> CHHapticEngine?) {
        self.engineFactory = engineFactory
    }

    func play(intensity: Float, sharpness: Float, duration: TimeInterval) {
        guard intensity > 0.01, duration > 0 else { stopPlayer(); return }
        do {
            if engine == nil {
                engine = engineFactory()
                engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
                engine?.stoppedHandler = { [weak self] _ in self?.engine = nil }
                try engine?.start()
            }
            guard let engine else { return }
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: min(1, intensity)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                ],
                relativeTime: 0,
                duration: min(duration, 5)
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            stopPlayer()
            player = try engine.makePlayer(with: pattern)
            try player?.start(atTime: CHHapticTimeImmediate)
        } catch {
            engine = nil
        }
    }

    private func stopPlayer() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
    }

    func stop() {
        stopPlayer()
        engine?.stop(completionHandler: nil)
        engine = nil
    }
}

/// 设备本身的震动（iPhone）。Mac 上没有震动马达，什么也不做。
final class DeviceRumble {
    static let shared = DeviceRumble()
    private lazy var player: RumblePlayer? = {
        #if os(iOS)
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        return RumblePlayer(engineFactory: { try? CHHapticEngine() })
        #else
        return nil
        #endif
    }()

    func play(intensity: Float, sharpness: Float, duration: TimeInterval) {
        player?.play(intensity: intensity, sharpness: sharpness, duration: duration)
    }
}

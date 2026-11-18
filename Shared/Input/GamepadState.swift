import Foundation

/// 手柄按键位掩码，数值与 Xbox 串流输入协议一致。
struct GamepadButtons: OptionSet, Hashable, Codable {
    let rawValue: UInt16

    static let nexus         = GamepadButtons(rawValue: 1 << 1)   // 2
    static let menu          = GamepadButtons(rawValue: 1 << 2)   // 4
    static let view          = GamepadButtons(rawValue: 1 << 3)   // 8
    static let a             = GamepadButtons(rawValue: 1 << 4)   // 16
    static let b             = GamepadButtons(rawValue: 1 << 5)   // 32
    static let x             = GamepadButtons(rawValue: 1 << 6)   // 64
    static let y             = GamepadButtons(rawValue: 1 << 7)   // 128
    static let dpadUp        = GamepadButtons(rawValue: 1 << 8)   // 256
    static let dpadDown      = GamepadButtons(rawValue: 1 << 9)   // 512
    static let dpadLeft      = GamepadButtons(rawValue: 1 << 10)  // 1024
    static let dpadRight     = GamepadButtons(rawValue: 1 << 11)  // 2048
    static let leftShoulder  = GamepadButtons(rawValue: 1 << 12)  // 4096
    static let rightShoulder = GamepadButtons(rawValue: 1 << 13)  // 8192
    static let leftThumb     = GamepadButtons(rawValue: 1 << 14)  // 16384
    static let rightThumb    = GamepadButtons(rawValue: 1 << 15)  // 32768
}

/// 二维摇杆值，x 向右为正，y 向上为正，范围 -1...1。
struct StickValue: Equatable, Hashable, Codable {
    var x: Float
    var y: Float

    static let zero = StickValue(x: 0, y: 0)

    var magnitude: Float { (x * x + y * y).squareRoot() }

    /// 圆形死区 + 重新映射到 0...1，避免死区边缘跳变
    func applyingDeadzone(_ deadzone: Float) -> StickValue {
        let m = magnitude
        guard m > deadzone, m > 0 else { return .zero }
        let clamped = min(m, 1)
        let scaled = (clamped - deadzone) / (1 - deadzone)
        return StickValue(x: x / m * scaled, y: y / m * scaled)
    }

    func clamped() -> StickValue {
        let m = magnitude
        guard m > 1 else { return self }
        return StickValue(x: x / m, y: y / m)
    }
}

/// 统一的手柄状态：触控、键盘、蓝牙手柄都写成这个结构，再合并。
struct GamepadState: Equatable, Hashable {
    var buttons: GamepadButtons = []
    var leftStick: StickValue = .zero
    var rightStick: StickValue = .zero
    var leftTrigger: Float = 0    // 0...1
    var rightTrigger: Float = 0   // 0...1

    static let neutral = GamepadState()

    var isNeutral: Bool { self == .neutral }

    /// 合并：按键取并集，摇杆取幅度大的，扳机取最大值
    func merged(with other: GamepadState) -> GamepadState {
        var out = GamepadState()
        out.buttons = buttons.union(other.buttons)
        out.leftStick = leftStick.magnitude >= other.leftStick.magnitude ? leftStick : other.leftStick
        out.rightStick = rightStick.magnitude >= other.rightStick.magnitude ? rightStick : other.rightStick
        out.leftTrigger = max(leftTrigger, other.leftTrigger)
        out.rightTrigger = max(rightTrigger, other.rightTrigger)
        return out
    }

    static func merge(_ states: [GamepadState]) -> GamepadState {
        states.reduce(GamepadState.neutral) { $0.merged(with: $1) }
    }

    /// 同时按下 View + Menu 时视为 Xbox 键（与参考实现一致的兼容处理）
    func applyingNexusChord() -> GamepadState {
        guard buttons.contains(.view), buttons.contains(.menu) else { return self }
        var copy = self
        copy.buttons.remove(.view)
        copy.buttons.remove(.menu)
        copy.buttons.insert(.nexus)
        return copy
    }
}

/// 输入来源，用于合并与界面上显示当前输入方式
enum InputSourceID: Hashable {
    case touch
    case keyboard
    case controller(String)
}

/// 线程安全的输入汇总：UI 线程写入，发送线程读取。
final class InputHub {
    static let shared = InputHub()

    private let lock = NSLock()
    private var states: [InputSourceID: GamepadState] = [:]

    func update(_ source: InputSourceID, _ state: GamepadState) {
        lock.lock(); defer { lock.unlock() }
        states[source] = state
    }

    func remove(_ source: InputSourceID) {
        lock.lock(); defer { lock.unlock() }
        states.removeValue(forKey: source)
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        states.removeAll()
    }

    func current() -> GamepadState {
        lock.lock(); defer { lock.unlock() }
        return GamepadState.merge(Array(states.values)).applyingNexusChord()
    }
}

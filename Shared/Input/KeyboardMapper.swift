import Foundation

/// 可被键盘绑定的手柄功能
enum GamepadControl: String, CaseIterable, Codable, Hashable, Identifiable {
    case leftStickUp, leftStickDown, leftStickLeft, leftStickRight
    case rightStickUp, rightStickDown, rightStickLeft, rightStickRight
    case a, b, x, y
    case leftShoulder, rightShoulder, leftTrigger, rightTrigger
    case dpadUp, dpadDown, dpadLeft, dpadRight
    case view, menu, nexus
    case leftThumb, rightThumb

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .leftStickUp: return String(localized: "左摇杆 上")
        case .leftStickDown: return String(localized: "左摇杆 下")
        case .leftStickLeft: return String(localized: "左摇杆 左")
        case .leftStickRight: return String(localized: "左摇杆 右")
        case .rightStickUp: return String(localized: "右摇杆 上")
        case .rightStickDown: return String(localized: "右摇杆 下")
        case .rightStickLeft: return String(localized: "右摇杆 左")
        case .rightStickRight: return String(localized: "右摇杆 右")
        case .a: return "A"
        case .b: return "B"
        case .x: return "X"
        case .y: return "Y"
        case .leftShoulder: return "LB"
        case .rightShoulder: return "RB"
        case .leftTrigger: return "LT"
        case .rightTrigger: return "RT"
        case .dpadUp: return String(localized: "十字键 上")
        case .dpadDown: return String(localized: "十字键 下")
        case .dpadLeft: return String(localized: "十字键 左")
        case .dpadRight: return String(localized: "十字键 右")
        case .view: return String(localized: "视图键")
        case .menu: return String(localized: "菜单键")
        case .nexus: return String(localized: "Xbox 键")
        case .leftThumb: return String(localized: "L3（按下左摇杆）")
        case .rightThumb: return String(localized: "R3（按下右摇杆）")
        }
    }

    /// 键位映射页的分组
    enum Group: String, CaseIterable {
        case sticks, face, shoulders, dpad, system
        var title: String {
            switch self {
            case .sticks: return String(localized: "摇杆")
            case .face: return String(localized: "功能键")
            case .shoulders: return String(localized: "肩键与扳机")
            case .dpad: return String(localized: "十字键")
            case .system: return String(localized: "系统键")
            }
        }
    }

    var group: Group {
        switch self {
        case .leftStickUp, .leftStickDown, .leftStickLeft, .leftStickRight,
             .rightStickUp, .rightStickDown, .rightStickLeft, .rightStickRight,
             .leftThumb, .rightThumb:
            return .sticks
        case .a, .b, .x, .y: return .face
        case .leftShoulder, .rightShoulder, .leftTrigger, .rightTrigger: return .shoulders
        case .dpadUp, .dpadDown, .dpadLeft, .dpadRight: return .dpad
        case .view, .menu, .nexus: return .system
        }
    }
}

/// 一个物理输入：键盘按键（用名字保存，平台层转换成 GCKeyCode）或鼠标按键
enum KeyInput: Hashable, Codable {
    case key(String)
    case mouseLeft
    case mouseRight

    var displayName: String {
        switch self {
        case .key(let name): return KeyInput.prettyNames[name] ?? name.uppercased()
        case .mouseLeft: return String(localized: "鼠标左键")
        case .mouseRight: return String(localized: "鼠标右键")
        }
    }

    static let prettyNames: [String: String] = [
        "space": "Space", "escape": "Esc", "return": "Enter", "tab": "Tab",
        "backspace": "Backspace", "leftShift": "Shift", "rightShift": "Right Shift",
        "leftControl": "Control", "leftOption": "Option", "leftCommand": "Command",
        "up": "\u{2191}", "down": "\u{2193}", "left": "\u{2190}", "right": "\u{2192}",
        "grave": "`", "minus": "-", "equals": "=", "comma": ",", "period": ".", "slash": "/",
        "semicolon": ";", "quote": "'", "leftBracket": "[", "rightBracket": "]", "backslash": "\\"
    ]
}

/// 键位绑定表：每个功能可绑定多个物理输入
struct KeyBindings: Codable, Equatable {
    var map: [GamepadControl: [KeyInput]]

    static let `default` = KeyBindings(map: [
        .leftStickUp: [.key("w")], .leftStickDown: [.key("s")],
        .leftStickLeft: [.key("a")], .leftStickRight: [.key("d")],
        .rightStickUp: [.key("up")], .rightStickDown: [.key("down")],
        .rightStickLeft: [.key("left")], .rightStickRight: [.key("right")],
        .a: [.key("space")], .b: [.key("escape"), .key("backspace")],
        .x: [.key("f")], .y: [.key("r")],
        .leftShoulder: [.key("q")], .rightShoulder: [.key("e")],
        .leftTrigger: [.key("leftShift"), .mouseRight], .rightTrigger: [.mouseLeft],
        .dpadUp: [.key("i")], .dpadDown: [.key("k")], .dpadLeft: [.key("j")], .dpadRight: [.key("l")],
        .view: [.key("tab")], .menu: [.key("return")], .nexus: [.key("h")],
        .leftThumb: [.key("c")], .rightThumb: [.key("v")]
    ])

    func inputs(for control: GamepadControl) -> [KeyInput] { map[control] ?? [] }

    /// 找到已经绑定了该输入的功能（用于冲突提示）
    func control(boundTo input: KeyInput) -> GamepadControl? {
        map.first { $0.value.contains(input) }?.key
    }

    /// 绑定新输入作为该功能的主键。如果它已被别的功能占用，则把本功能原来的主键交换过去。
    /// 返回被交换的功能（若有）。
    @discardableResult
    mutating func bind(_ input: KeyInput, to control: GamepadControl) -> GamepadControl? {
        let previousPrimary = map[control]?.first
        var swapped: GamepadControl? = nil
        if let other = self.control(boundTo: input), other != control {
            var otherInputs = map[other] ?? []
            otherInputs.removeAll { $0 == input }
            if let previousPrimary, !otherInputs.contains(previousPrimary) {
                otherInputs.insert(previousPrimary, at: 0)
            }
            map[other] = otherInputs
            swapped = other
        }
        var inputs = map[control] ?? []
        inputs.removeAll { $0 == input }
        if !inputs.isEmpty { inputs.removeFirst() }
        inputs.insert(input, at: 0)
        map[control] = inputs
        return swapped
    }

    // Codable：字典的 key 是枚举，编码成 [String: [KeyInput]]
    init(map: [GamepadControl: [KeyInput]]) { self.map = map }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode([String: [KeyInput]].self)
        var map: [GamepadControl: [KeyInput]] = [:]
        for (k, v) in raw { if let c = GamepadControl(rawValue: k) { map[c] = v } }
        self.map = map
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Dictionary(uniqueKeysWithValues: map.map { ($0.key.rawValue, $0.value) }))
    }
}

/// 把当前按下的物理输入映射成手柄状态（纯函数，可单元测试）
enum KeyboardMapper {
    static func state(pressed: Set<KeyInput>, bindings: KeyBindings) -> GamepadState {
        func isDown(_ c: GamepadControl) -> Bool {
            bindings.inputs(for: c).contains { pressed.contains($0) }
        }

        var s = GamepadState()
        let buttonMap: [(GamepadControl, GamepadButtons)] = [
            (.a, .a), (.b, .b), (.x, .x), (.y, .y),
            (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
            (.dpadUp, .dpadUp), (.dpadDown, .dpadDown), (.dpadLeft, .dpadLeft), (.dpadRight, .dpadRight),
            (.view, .view), (.menu, .menu), (.nexus, .nexus),
            (.leftThumb, .leftThumb), (.rightThumb, .rightThumb)
        ]
        for (control, button) in buttonMap where isDown(control) {
            s.buttons.insert(button)
        }
        s.leftTrigger = isDown(.leftTrigger) ? 1 : 0
        s.rightTrigger = isDown(.rightTrigger) ? 1 : 0

        func axis(_ neg: GamepadControl, _ pos: GamepadControl) -> Float {
            (isDown(pos) ? 1 : 0) - (isDown(neg) ? 1 : 0)
        }
        s.leftStick = StickValue(x: axis(.leftStickLeft, .leftStickRight),
                                 y: axis(.leftStickDown, .leftStickUp)).clamped()
        s.rightStick = StickValue(x: axis(.rightStickLeft, .rightStickRight),
                                  y: axis(.rightStickDown, .rightStickUp)).clamped()
        return s
    }
}

import SwiftUI

/// 屏幕上的一个控件块
enum TouchElementKind: String, Codable, CaseIterable, Identifiable {
    case leftStick, rightStick, faceButtons, dpad
    case leftShoulder, rightShoulder, leftTrigger, rightTrigger
    case view, menu, nexus

    var id: String { rawValue }

    /// 缩放为 1 时的基础尺寸（pt）
    var baseSize: CGSize {
        switch self {
        case .leftStick, .rightStick: return CGSize(width: 132, height: 132)
        case .faceButtons: return CGSize(width: 156, height: 156)
        case .dpad: return CGSize(width: 124, height: 124)
        case .leftShoulder, .rightShoulder: return CGSize(width: 78, height: 38)
        case .leftTrigger, .rightTrigger: return CGSize(width: 78, height: 50)
        case .view, .menu, .nexus: return CGSize(width: 40, height: 40)
        }
    }

    var displayName: String {
        switch self {
        case .leftStick: return String(localized: "左摇杆")
        case .rightStick: return String(localized: "右摇杆")
        case .faceButtons: return "A B X Y"
        case .dpad: return String(localized: "十字键")
        case .leftShoulder: return "LB"
        case .rightShoulder: return "RB"
        case .leftTrigger: return "LT"
        case .rightTrigger: return "RT"
        case .view: return String(localized: "视图键")
        case .menu: return String(localized: "菜单键")
        case .nexus: return String(localized: "Xbox 键")
        }
    }
}

struct TouchElement: Codable, Hashable, Identifiable {
    var kind: TouchElementKind
    /// 中心点，按画布宽高的比例保存（0...1），换设备也不会错位
    var centerX: Double
    var centerY: Double
    var scale: Double = 1
    var opacity: Double = 1
    var hidden: Bool = false

    var id: String { kind.rawValue }

    func center(in size: CGSize) -> CGPoint {
        CGPoint(x: centerX * size.width, y: centerY * size.height)
    }

    func frame(in size: CGSize, globalScale: Double) -> CGRect {
        let s = kind.baseSize
        let k = CGFloat(scale * globalScale)
        let c = center(in: size)
        return CGRect(x: c.x - s.width * k / 2, y: c.y - s.height * k / 2, width: s.width * k, height: s.height * k)
    }
}

struct TouchLayoutScheme: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var elements: [TouchElement]
    var builtIn: Bool

    func element(_ kind: TouchElementKind) -> TouchElement? {
        elements.first { $0.kind == kind }
    }

    static func make(_ name: String, builtIn: Bool = true, _ values: [(TouchElementKind, Double, Double, Double)]) -> TouchLayoutScheme {
        TouchLayoutScheme(
            id: UUID(),
            name: name,
            elements: values.map { TouchElement(kind: $0.0, centerX: $0.1, centerY: $0.2, scale: $0.3) },
            builtIn: builtIn
        )
    }

    static var standard: TouchLayoutScheme {
        make(String(localized: "默认"), [
            (.leftStick, 0.17, 0.64, 1),
            (.dpad, 0.33, 0.82, 0.9),
            (.rightStick, 0.67, 0.80, 0.95),
            (.faceButtons, 0.86, 0.56, 1),
            (.leftTrigger, 0.07, 0.13, 1),
            (.leftShoulder, 0.18, 0.13, 1),
            (.rightShoulder, 0.82, 0.13, 1),
            (.rightTrigger, 0.93, 0.13, 1),
            (.view, 0.43, 0.09, 1),
            (.nexus, 0.50, 0.09, 1),
            (.menu, 0.57, 0.09, 1)
        ])
    }

    static var racing: TouchLayoutScheme {
        make(String(localized: "赛车"), [
            (.leftStick, 0.17, 0.66, 1),
            (.dpad, 0.36, 0.86, 0.75),
            (.rightStick, 0.62, 0.86, 0.75),
            (.faceButtons, 0.90, 0.36, 0.8),
            (.leftTrigger, 0.33, 0.58, 1.35),
            (.leftShoulder, 0.08, 0.13, 1),
            (.rightShoulder, 0.92, 0.13, 1),
            (.rightTrigger, 0.80, 0.74, 1.6),
            (.view, 0.43, 0.09, 1),
            (.nexus, 0.50, 0.09, 1),
            (.menu, 0.57, 0.09, 1)
        ])
    }

    static var shooter: TouchLayoutScheme {
        make(String(localized: "射击"), [
            (.leftStick, 0.16, 0.66, 1.05),
            (.dpad, 0.32, 0.86, 0.75),
            (.rightStick, 0.68, 0.72, 1.25),
            (.faceButtons, 0.89, 0.66, 0.85),
            (.leftTrigger, 0.07, 0.30, 1.2),
            (.leftShoulder, 0.07, 0.12, 1),
            (.rightShoulder, 0.93, 0.12, 1),
            (.rightTrigger, 0.89, 0.32, 1.35),
            (.view, 0.43, 0.09, 1),
            (.nexus, 0.50, 0.09, 1),
            (.menu, 0.57, 0.09, 1)
        ])
    }
}

/// 保存多套布局方案（只在主线程使用）
final class TouchLayoutStore: ObservableObject {
    static let shared = TouchLayoutStore()

    @Published private(set) var schemes: [TouchLayoutScheme]
    @Published private(set) var currentId: UUID

    private let key = "touchLayouts.v1"
    private let currentKey = "touchLayouts.current"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let list = try? JSONDecoder().decode([TouchLayoutScheme].self, from: data), !list.isEmpty {
            schemes = list
        } else {
            schemes = [.standard, .racing, .shooter]
        }
        if let raw = UserDefaults.standard.string(forKey: currentKey), let id = UUID(uuidString: raw),
           schemes.contains(where: { $0.id == id }) {
            currentId = id
        } else {
            currentId = schemes[0].id
        }
    }

    var current: TouchLayoutScheme {
        schemes.first { $0.id == currentId } ?? schemes[0]
    }

    func select(_ id: UUID) {
        guard schemes.contains(where: { $0.id == id }) else { return }
        currentId = id
        UserDefaults.standard.set(id.uuidString, forKey: currentKey)
    }

    func update(_ scheme: TouchLayoutScheme) {
        guard let i = schemes.firstIndex(where: { $0.id == scheme.id }) else { return }
        schemes[i] = scheme
        persist()
    }

    @discardableResult
    func createScheme(from base: TouchLayoutScheme, name: String) -> TouchLayoutScheme {
        var copy = base
        copy.id = UUID()
        copy.name = name
        copy.builtIn = false
        schemes.append(copy)
        persist()
        select(copy.id)
        return copy
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = schemes.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        schemes[i].name = trimmed
        persist()
    }

    func delete(_ id: UUID) {
        guard schemes.count > 1, let i = schemes.firstIndex(where: { $0.id == id }) else { return }
        schemes.remove(at: i)
        if currentId == id { select(schemes[0].id) }
        persist()
    }

    /// 恢复该方案的默认位置（内置方案恢复到出厂值，自定义方案恢复到「默认」）
    func resetToDefault(_ id: UUID) {
        guard let i = schemes.firstIndex(where: { $0.id == id }) else { return }
        let name = schemes[i].name
        let reference: TouchLayoutScheme
        switch i {
        case 0 where schemes[i].builtIn: reference = .standard
        case 1 where schemes[i].builtIn: reference = .racing
        case 2 where schemes[i].builtIn: reference = .shooter
        default: reference = .standard
        }
        schemes[i].elements = reference.elements
        schemes[i].name = name
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(schemes) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

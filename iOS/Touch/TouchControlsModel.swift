import SwiftUI
import UIKit

/// 屏幕按键的逻辑按钮
enum TouchControlID: Hashable {
    case a, b, x, y
    case dpadUp, dpadDown, dpadLeft, dpadRight
    case lb, rb, lt, rt
    case view, menu, nexus
    case l3, r3

    var gamepadButton: GamepadButtons? {
        switch self {
        case .a: return .a
        case .b: return .b
        case .x: return .x
        case .y: return .y
        case .dpadUp: return .dpadUp
        case .dpadDown: return .dpadDown
        case .dpadLeft: return .dpadLeft
        case .dpadRight: return .dpadRight
        case .lb: return .leftShoulder
        case .rb: return .rightShoulder
        case .view: return .view
        case .menu: return .menu
        case .nexus: return .nexus
        case .l3: return .leftThumb
        case .r3: return .rightThumb
        case .lt, .rt: return nil
        }
    }
}

/// 摇杆的显示状态
struct StickVisual: Equatable {
    var active = false
    var origin: CGPoint = .zero      // 圆心（画布坐标）
    var knob: CGPoint = .zero        // 圆钮相对圆心的偏移（pt）
    var value: StickValue = .zero    // 输出值
}

/// 处理多点触控 → 手柄状态。所有触摸都由一个 UIView 统一接收，
/// 这样可以支持：浮动摇杆、手指在按键间滑动、两键同时按、双击摇杆 = L3/R3、三指下滑呼出菜单。
@MainActor
final class TouchControlsModel: ObservableObject {
    @Published private(set) var pressed: Set<TouchControlID> = []
    @Published private(set) var leftStick = StickVisual()
    @Published private(set) var rightStick = StickVisual()
    @Published private(set) var triggerValues: [TouchControlID: Float] = [:]
    @Published private(set) var isIdle = false

    var layout: TouchLayoutScheme = .standard
    var canvasSize: CGSize = .zero
    var globalScale: Double = 1
    var deadzone: Float = 0.08
    var floatingLeftStick = true
    var triggerMode: TriggerMode = .instant
    var active = true {
        didSet { if !active { releaseAll() } }
    }
    var onMenuGesture: (() -> Void)?

    private enum Role {
        case leftStick(origin: CGPoint, l3: Bool)
        case rightStick(origin: CGPoint, r3: Bool)
        case face
        case dpad
        case single(TouchControlID, CGRect)
        case trigger(TouchControlID, CGRect, start: CFTimeInterval)
        case none
    }

    private var roles: [ObjectIdentifier: Role] = [:]
    private var touchPoints: [ObjectIdentifier: CGPoint] = [:]
    private var touchStarts: [ObjectIdentifier: CGPoint] = [:]
    private var lastStickRelease: [Bool: (time: CFTimeInterval, point: CGPoint)] = [:]   // true = 左
    private var idleTask: Task<Void, Never>?
    private var rampLink: CADisplayLink?
    private var menuGestureFired = false

    // MARK: 触摸事件

    func touchesBegan(_ touches: [(ObjectIdentifier, CGPoint)]) {
        markActivity()
        for (id, p) in touches {
            touchPoints[id] = p
            touchStarts[id] = p
            roles[id] = active ? role(for: p) : Role.none
        }
        if touchPoints.count < 3 { menuGestureFired = false }
        recompute()
    }

    func touchesMoved(_ touches: [(ObjectIdentifier, CGPoint)]) {
        markActivity()
        for (id, p) in touches { touchPoints[id] = p }
        if detectMenuGesture() { return }
        recompute()
    }

    func touchesEnded(_ ids: [ObjectIdentifier]) {
        let now = CACurrentMediaTime()
        for id in ids {
            if let role = roles[id], let p = touchPoints[id] {
                switch role {
                case .leftStick: lastStickRelease[true] = (now, p)
                case .rightStick: lastStickRelease[false] = (now, p)
                default: break
                }
            }
            roles.removeValue(forKey: id)
            touchPoints.removeValue(forKey: id)
            touchStarts.removeValue(forKey: id)
        }
        recompute()
    }

    func releaseAll() {
        roles.removeAll()
        touchPoints.removeAll()
        touchStarts.removeAll()
        recompute()
    }

    // MARK: 角色分配

    private func frame(_ kind: TouchElementKind, slack: CGFloat = 0) -> CGRect? {
        guard let el = layout.element(kind), !el.hidden else { return nil }
        return el.frame(in: canvasSize, globalScale: globalScale).insetBy(dx: -slack, dy: -slack)
    }

    private func role(for p: CGPoint) -> Role {
        // 1. 按键优先
        if let f = frame(.faceButtons, slack: 14), f.contains(p) { return .face }
        if let f = frame(.dpad, slack: 12), f.contains(p) { return .dpad }
        let singles: [(TouchElementKind, TouchControlID)] = [
            (.leftShoulder, .lb), (.rightShoulder, .rb), (.view, .view), (.menu, .menu), (.nexus, .nexus)
        ]
        for (kind, id) in singles {
            if let f = frame(kind, slack: kind == .view || kind == .menu || kind == .nexus ? 8 : 12), f.contains(p) {
                return .single(id, f.insetBy(dx: -24, dy: -24))
            }
        }
        for (kind, id) in [(TouchElementKind.leftTrigger, TouchControlID.lt), (.rightTrigger, .rt)] {
            if let f = frame(kind, slack: 12), f.contains(p) {
                return .trigger(id, f.insetBy(dx: -24, dy: -24), start: CACurrentMediaTime())
            }
        }

        // 2. 右摇杆（固定位置，按在摇杆区域任意处）
        if let f = frame(.rightStick, slack: 30), f.contains(p) {
            let center = CGPoint(x: f.midX, y: f.midY)
            return .rightStick(origin: center, r3: isDoubleTap(left: false, at: p))
        }

        // 3. 左摇杆：浮动模式下左半屏下 2/3 任意位置都可以
        if floatingLeftStick {
            if p.x < canvasSize.width * 0.5, p.y > canvasSize.height * 0.30 {
                return .leftStick(origin: p, l3: isDoubleTap(left: true, at: p))
            }
        } else if let f = frame(.leftStick, slack: 30), f.contains(p) {
            return .leftStick(origin: CGPoint(x: f.midX, y: f.midY), l3: isDoubleTap(left: true, at: p))
        }
        return .none
    }

    private func isDoubleTap(left: Bool, at p: CGPoint) -> Bool {
        guard let last = lastStickRelease[left] else { return false }
        let dt = CACurrentMediaTime() - last.time
        let dist = hypot(p.x - last.point.x, p.y - last.point.y)
        return dt < 0.3 && dist < 60
    }

    // MARK: 计算输出

    private func recompute() {
        var newPressed = Set<TouchControlID>()
        var left = StickVisual()
        var right = StickVisual()
        var triggers: [TouchControlID: Float] = [:]
        var needsRamp = false
        let now = CACurrentMediaTime()

        for (id, role) in roles {
            guard let p = touchPoints[id] else { continue }
            switch role {
            case .leftStick(let origin, let l3):
                left = stickVisual(origin: origin, point: p, kind: .leftStick)
                if l3 { newPressed.insert(.l3) }
            case .rightStick(let origin, let r3):
                right = stickVisual(origin: origin, point: p, kind: .rightStick)
                if r3 { newPressed.insert(.r3) }
            case .face:
                newPressed.formUnion(faceButtons(at: p))
            case .dpad:
                newPressed.formUnion(dpadDirections(at: p))
            case .single(let control, let area):
                if area.contains(p) { newPressed.insert(control) }
            case .trigger(let control, let area, let start):
                if area.contains(p) {
                    newPressed.insert(control)
                    if triggerMode == .ramp {
                        let v = Float(min(1, (now - start) / 0.35))
                        triggers[control] = max(triggers[control] ?? 0, max(0.15, v))
                        if v < 1 { needsRamp = true }
                    } else {
                        triggers[control] = 1
                    }
                }
            case .none:
                break
            }
        }

        let newlyPressed = newPressed.subtracting(pressed)
        if !newlyPressed.isEmpty { Haptics.controlPress() }

        if newPressed != pressed { pressed = newPressed }
        if left != leftStick { leftStick = left }
        if right != rightStick { rightStick = right }
        if triggers != triggerValues { triggerValues = triggers }
        updateRampLink(needsRamp)

        // 写入输入汇总
        var state = GamepadState()
        for control in newPressed {
            if let b = control.gamepadButton { state.buttons.insert(b) }
        }
        state.leftStick = left.value
        state.rightStick = right.value
        state.leftTrigger = triggers[.lt] ?? 0
        state.rightTrigger = triggers[.rt] ?? 0
        InputHub.shared.update(.touch, state)
    }

    private func stickVisual(origin: CGPoint, point: CGPoint, kind: TouchElementKind) -> StickVisual {
        let el = layout.element(kind)
        let radius = kind.baseSize.width * CGFloat((el?.scale ?? 1) * globalScale) / 2 * 0.72
        var dx = point.x - origin.x
        var dy = point.y - origin.y
        let dist = hypot(dx, dy)
        // 超出外环仍保持满偏，圆钮停在边缘
        if dist > radius, dist > 0 {
            dx = dx / dist * radius
            dy = dy / dist * radius
        }
        let raw = StickValue(x: Float(dx / radius), y: Float(-dy / radius))
        return StickVisual(active: true, origin: origin, knob: CGPoint(x: dx, y: dy),
                           value: raw.applyingDeadzone(deadzone))
    }

    private func faceButtons(at p: CGPoint) -> Set<TouchControlID> {
        guard let f = frame(.faceButtons) else { return [] }
        let c = CGPoint(x: f.midX, y: f.midY)
        let offset = f.width * 0.33
        let buttonRadius = f.width * 0.19
        let centers: [(TouchControlID, CGPoint)] = [
            (.a, CGPoint(x: c.x, y: c.y + offset)),
            (.b, CGPoint(x: c.x + offset, y: c.y)),
            (.x, CGPoint(x: c.x - offset, y: c.y)),
            (.y, CGPoint(x: c.x, y: c.y - offset))
        ]
        // 扩大命中半径，让手指落在两键之间时两个都触发
        let hitRadius = buttonRadius * 1.35
        var result = Set<TouchControlID>()
        for (id, center) in centers where hypot(p.x - center.x, p.y - center.y) <= hitRadius {
            result.insert(id)
        }
        if result.isEmpty, f.insetBy(dx: -30, dy: -30).contains(p) {
            // 在簇内但不在任何键上：取最近的键
            if let nearest = centers.min(by: { hypot(p.x - $0.1.x, p.y - $0.1.y) < hypot(p.x - $1.1.x, p.y - $1.1.y) }),
               hypot(p.x - nearest.1.x, p.y - nearest.1.y) < buttonRadius * 1.8 {
                result.insert(nearest.0)
            }
        }
        return result
    }

    private func dpadDirections(at p: CGPoint) -> Set<TouchControlID> {
        guard let f = frame(.dpad) else { return [] }
        let dx = p.x - f.midX
        let dy = p.y - f.midY
        let len = hypot(dx, dy)
        guard len > f.width * 0.12, len < f.width * 1.1 else { return [] }
        let k: CGFloat = 0.38   // cos(67.5°)，大于这个分量就算按下该方向，支持斜向
        var result = Set<TouchControlID>()
        if -dy > k * len { result.insert(.dpadUp) }
        if dy > k * len { result.insert(.dpadDown) }
        if -dx > k * len { result.insert(.dpadLeft) }
        if dx > k * len { result.insert(.dpadRight) }
        return result
    }

    // MARK: 三指下滑

    private func detectMenuGesture() -> Bool {
        guard touchPoints.count >= 3, !menuGestureFired else { return false }
        let deltas = touchPoints.compactMap { id, p -> CGFloat? in
            guard let s = touchStarts[id] else { return nil }
            return p.y - s.y
        }
        guard deltas.count >= 3, deltas.allSatisfy({ $0 > 50 }) else { return false }
        menuGestureFired = true
        releaseAll()
        onMenuGesture?()
        return true
    }

    // MARK: 空闲淡出

    private func markActivity() {
        if isIdle { withAnimation(Theme.Motion.gentle) { isIdle = false } }
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 1.2)) { self?.isIdle = true }
        }
    }

    // MARK: 扳机渐增

    private func updateRampLink(_ needed: Bool) {
        if needed, rampLink == nil {
            let link = CADisplayLink(target: RampTarget { [weak self] in self?.recompute() }, selector: #selector(RampTarget.tick))
            link.add(to: .main, forMode: .common)
            rampLink = link
        } else if !needed, let link = rampLink {
            link.invalidate()
            rampLink = nil
        }
    }
}

private final class RampTarget: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func tick() { action() }
}

/// 接收所有触摸的透明 UIView
final class TouchSurfaceView: UIView {
    weak var model: TouchControlsModel?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func points(_ touches: Set<UITouch>) -> [(ObjectIdentifier, CGPoint)] {
        touches.map { (ObjectIdentifier($0), $0.location(in: self)) }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let pts = points(touches)
        model?.touchesBegan(pts)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let pts = points(touches)
        model?.touchesMoved(pts)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let ids = touches.map { ObjectIdentifier($0) }
        model?.touchesEnded(ids)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        let ids = touches.map { ObjectIdentifier($0) }
        model?.touchesEnded(ids)
    }
}

struct TouchSurface: UIViewRepresentable {
    let model: TouchControlsModel

    func makeUIView(context: Context) -> TouchSurfaceView {
        let view = TouchSurfaceView(frame: .zero)
        view.model = model
        return view
    }

    func updateUIView(_ uiView: TouchSurfaceView, context: Context) {
        uiView.model = model
    }
}

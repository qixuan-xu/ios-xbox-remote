import SwiftUI

/// 串流页上的屏幕手柄
struct TouchControlsView: View {
    var active: Bool
    var onMenuGesture: () -> Void

    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var store = TouchLayoutStore.shared
    @StateObject private var model = TouchControlsModel()

    var body: some View {
        GeometryReader { geo in
            let layout = store.current
            ZStack {
                ForEach(layout.elements.filter { !$0.hidden }) { element in
                    visual(for: element, size: geo.size)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .opacity(opacity)
            .allowsHitTesting(false)
            .overlay(TouchSurface(model: model))
            .onAppear { configure(size: geo.size, layout: layout) }
            .onChange(of: geo.size) { configure(size: $0, layout: store.current) }
            .onChange(of: store.current) { configure(size: geo.size, layout: $0) }
            .onChange(of: settings.buttonScale) { _ in configure(size: geo.size, layout: store.current) }
            .onChange(of: settings.stickDeadzone) { _ in configure(size: geo.size, layout: store.current) }
            .onChange(of: settings.floatingLeftStick) { _ in configure(size: geo.size, layout: store.current) }
            .onChange(of: settings.triggerMode) { _ in configure(size: geo.size, layout: store.current) }
            .onChange(of: active) { model.active = $0 }
        }
        .onDisappear {
            model.releaseAll()
            InputHub.shared.remove(.touch)
        }
        .accessibilityHidden(true)
    }

    private var opacity: Double {
        let base = settings.controlsOpacity
        return model.isIdle ? min(base, 0.3) : base
    }

    private func configure(size: CGSize, layout: TouchLayoutScheme) {
        model.canvasSize = size
        model.layout = layout
        model.globalScale = settings.buttonScale
        model.deadzone = Float(settings.stickDeadzone)
        model.floatingLeftStick = settings.floatingLeftStick
        model.triggerMode = settings.triggerMode
        model.active = active
        model.onMenuGesture = onMenuGesture
    }

    @ViewBuilder
    private func visual(for element: TouchElement, size: CGSize) -> some View {
        let frame = element.frame(in: size, globalScale: settings.buttonScale)
        let elementOpacity = element.opacity
        Group {
            switch element.kind {
            case .leftStick:
                let v = model.leftStick
                if v.active {
                    StickVisualView(visual: v, diameter: frame.width, label: "L")
                        .position(v.origin)
                        .transition(.opacity)
                } else {
                    // 空闲时在默认位置显示一个淡淡的摇杆
                    StickVisualView(visual: StickVisual(), diameter: frame.width, label: "L")
                        .opacity(settings.floatingLeftStick ? 0.45 : 1)
                        .position(x: frame.midX, y: frame.midY)
                }
            case .rightStick:
                StickVisualView(visual: model.rightStick, diameter: frame.width, label: "R")
                    .position(x: frame.midX, y: frame.midY)
            default:
                ElementVisual(kind: element.kind, frame: frame, pressed: model.pressed, triggerValues: model.triggerValues)
                    .position(x: frame.midX, y: frame.midY)
            }
        }
        .opacity(elementOpacity)
    }
}

/// 除摇杆以外的控件视觉（编辑器也复用）
struct ElementVisual: View {
    var kind: TouchElementKind
    var frame: CGRect
    var pressed: Set<TouchControlID> = []
    var triggerValues: [TouchControlID: Float] = [:]

    var body: some View {
        switch kind {
        case .faceButtons:
            FaceButtonCluster(pressed: pressed, size: frame.width)
        case .dpad:
            DPadVisual(pressed: pressed, size: frame.width)
        case .leftShoulder:
            ShoulderVisual(label: "LB", pressed: pressed.contains(.lb), size: frame.size)
        case .rightShoulder:
            ShoulderVisual(label: "RB", pressed: pressed.contains(.rb), size: frame.size)
        case .leftTrigger:
            TriggerVisual(label: "LT", isLeft: true, value: triggerValues[.lt] ?? 0, size: frame.size)
        case .rightTrigger:
            TriggerVisual(label: "RT", isLeft: false, value: triggerValues[.rt] ?? 0, size: frame.size)
        case .view:
            SystemButtonVisual(kind: .view, pressed: pressed.contains(.view), size: frame.width)
        case .menu:
            SystemButtonVisual(kind: .menu, pressed: pressed.contains(.menu), size: frame.width)
        case .nexus:
            SystemButtonVisual(kind: .nexus, pressed: pressed.contains(.nexus), size: frame.width)
        case .leftStick:
            StickVisualView(visual: StickVisual(), diameter: frame.width, label: "L")
        case .rightStick:
            StickVisualView(visual: StickVisual(), diameter: frame.width, label: "R")
        }
    }
}

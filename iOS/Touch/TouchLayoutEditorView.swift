import SwiftUI

/// 触控布局编辑器：拖动移动、双指缩放、对齐吸附、按键单独调整 / 隐藏、多套方案
struct TouchLayoutEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var store = TouchLayoutStore.shared

    @State private var scheme: TouchLayoutScheme = .standard
    @State private var selected: TouchElementKind?
    @State private var dragStart: [TouchElementKind: CGPoint] = [:]
    @State private var scaleStart: Double?
    @State private var guideX: CGFloat?
    @State private var guideY: CGFloat?
    @State private var renaming = false
    @State private var nameText = ""
    @State private var creating = false
    @State private var dirty = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                DemoVideoView()
                    .blur(radius: 18)
                    .overlay(Color.black.opacity(0.45))
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(Theme.Motion.snappy) { selected = nil } }

                // 8pt 网格（很淡）
                GridPattern(spacing: 8)
                    .stroke(Color.white.opacity(0.035), lineWidth: 0.5)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                // 对齐参考线
                if let guideX {
                    Rectangle().fill(Theme.Palette.accent.opacity(0.8)).frame(width: 1)
                        .position(x: guideX, y: geo.size.height / 2)
                        .frame(height: geo.size.height)
                        .allowsHitTesting(false)
                }
                if let guideY {
                    Rectangle().fill(Theme.Palette.accent.opacity(0.8)).frame(height: 1)
                        .position(x: geo.size.width / 2, y: guideY)
                        .frame(width: geo.size.width)
                        .allowsHitTesting(false)
                }

                ForEach(scheme.elements.filter { !$0.hidden }) { element in
                    editable(element, canvas: geo.size)
                }
            }
            .coordinateSpace(name: "editor")
        }
        .ignoresSafeArea()
        .overlay {
            VStack {
                topBar
                Spacer()
                bottomBar
            }
            .padding(Theme.Spacing.m)
            .animation(Theme.Motion.spring, value: selected)
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .onAppear {
            scheme = store.current
            OrientationLock.set(.landscape)
        }
        .alert("重命名方案", isPresented: $renaming) {
            TextField("名称", text: $nameText)
            Button("取消", role: .cancel) {}
            Button("保存") {
                store.rename(scheme.id, to: nameText)
                scheme.name = store.current.name
            }
        }
        .alert("新建方案", isPresented: $creating) {
            TextField("名称", text: $nameText)
            Button("取消", role: .cancel) {}
            Button("创建") {
                let name = nameText.trimmingCharacters(in: .whitespaces)
                scheme = store.createScheme(from: scheme, name: name.isEmpty ? String(localized: "自定义") : name)
            }
        } message: {
            Text("以当前布局为基础创建一套新方案。")
        }
    }

    // MARK: 可编辑控件

    private func editable(_ element: TouchElement, canvas: CGSize) -> some View {
        let frame = element.frame(in: canvas, globalScale: settings.buttonScale)
        let isSelected = selected == element.kind
        return ElementVisual(kind: element.kind, frame: frame)
            .opacity(element.opacity)
            .frame(width: frame.width, height: frame.height)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Theme.Palette.accent : Color.white.opacity(0.45),
                                  style: StrokeStyle(lineWidth: isSelected ? 1.5 : 1, dash: [5, 4]))
                    .padding(-8)
            )
            .overlay(alignment: .bottomTrailing) {
                if isSelected {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.black)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Theme.Palette.accent))
                        .offset(x: 14, y: 14)
                }
            }
            .contentShape(Rectangle().inset(by: -10))
            .position(x: frame.midX, y: frame.midY)
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named("editor"))
                    .onChanged { value in move(element.kind, translation: value.translation, canvas: canvas) }
                    .onEnded { _ in
                        dragStart[element.kind] = nil
                        withAnimation(Theme.Motion.snappy) { guideX = nil; guideY = nil }
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        if scaleStart == nil { scaleStart = element.scale; selected = element.kind }
                        update(element.kind) { $0.scale = min(1.8, max(0.6, (scaleStart ?? 1) * Double(value))) }
                    }
                    .onEnded { _ in scaleStart = nil }
            )
            .onTapGesture {
                Haptics.selection()
                withAnimation(Theme.Motion.snappy) { selected = isSelected ? nil : element.kind }
            }
            .animation(Theme.Motion.snappy, value: isSelected)
    }

    private func move(_ kind: TouchElementKind, translation: CGSize, canvas: CGSize) {
        guard let element = scheme.element(kind) else { return }
        if dragStart[kind] == nil {
            dragStart[kind] = element.center(in: canvas)
            selected = kind
        }
        guard let start = dragStart[kind] else { return }
        var x = start.x + translation.width
        var y = start.y + translation.height

        // 吸附到其他控件的中线（6pt 内），否则吸附到 8pt 网格
        let others = scheme.elements.filter { $0.kind != kind && !$0.hidden }.map { $0.center(in: canvas) }
        let snapThreshold: CGFloat = 6
        var gx: CGFloat? = nil, gy: CGFloat? = nil
        if let match = others.map(\.x).min(by: { abs($0 - x) < abs($1 - x) }), abs(match - x) < snapThreshold {
            x = match; gx = match
        } else if abs(x - canvas.width / 2) < snapThreshold {
            x = canvas.width / 2; gx = x
        } else {
            x = (x / 8).rounded() * 8
        }
        if let match = others.map(\.y).min(by: { abs($0 - y) < abs($1 - y) }), abs(match - y) < snapThreshold {
            y = match; gy = match
        } else {
            y = (y / 8).rounded() * 8
        }
        if (gx != nil && guideX == nil) || (gy != nil && guideY == nil) { Haptics.selection() }
        guideX = gx
        guideY = gy

        x = min(max(x, 20), canvas.width - 20)
        y = min(max(y, 20), canvas.height - 20)
        update(kind) {
            $0.centerX = Double(x / canvas.width)
            $0.centerY = Double(y / canvas.height)
        }
    }

    private func update(_ kind: TouchElementKind, _ change: (inout TouchElement) -> Void) {
        guard let i = scheme.elements.firstIndex(where: { $0.kind == kind }) else { return }
        change(&scheme.elements[i])
        dirty = true
    }

    // MARK: 顶部工具条

    private var topBar: some View {
        HStack(spacing: Theme.Spacing.s) {
            Menu {
                Section("方案") {
                    ForEach(store.schemes) { item in
                        Button {
                            saveIfNeeded()
                            store.select(item.id)
                            scheme = store.current
                            selected = nil
                        } label: {
                            if item.id == scheme.id { Label(item.name, systemImage: "checkmark") } else { Text(item.name) }
                        }
                    }
                }
                Button { nameText = ""; creating = true } label: { Label("新建方案", systemImage: "plus") }
                Button { nameText = scheme.name; renaming = true } label: { Label("重命名", systemImage: "pencil") }
                if store.schemes.count > 1 {
                    Button(role: .destructive) {
                        store.delete(scheme.id)
                        scheme = store.current
                    } label: { Label("删除方案", systemImage: "trash") }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(scheme.name)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                .padding(.horizontal, 14)
                .frame(height: 38)
                .glassCapsule()
            }

            Spacer()

            Button("恢复默认") {
                store.resetToDefault(scheme.id)
                withAnimation(Theme.Motion.spring) { scheme = store.current }
                dirty = false
                Haptics.impact()
            }
            .buttonStyle(TextButtonStyle(tint: Theme.Palette.textPrimary))
            .padding(.horizontal, 14)
            .frame(height: 38)
            .glassCapsule()

            Button {
                saveIfNeeded()
                dismiss()
            } label: {
                Text("完成")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Color.black.opacity(0.85))
                    .padding(.horizontal, 18)
                    .frame(height: 38)
                    .background(Capsule().fill(Theme.Palette.accent))
            }
            .buttonStyle(CardButtonStyle())
        }
    }

    // MARK: 底部工具条

    @ViewBuilder
    private var bottomBar: some View {
        if let kind = selected, let element = scheme.element(kind) {
            HStack(spacing: Theme.Spacing.l) {
                Text(kind.displayName)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .frame(minWidth: 70, alignment: .leading)
                sliderItem(icon: "arrow.up.left.and.arrow.down.right", value: Binding(
                    get: { element.scale }, set: { v in update(kind) { $0.scale = v } }), range: 0.6...1.8,
                           text: "\(Int(element.scale * 100))%")
                sliderItem(icon: "circle.lefthalf.filled", value: Binding(
                    get: { element.opacity }, set: { v in update(kind) { $0.opacity = v } }), range: 0.2...1,
                           text: "\(Int(element.opacity * 100))%")
                Button {
                    withAnimation(Theme.Motion.spring) {
                        update(kind) { $0.hidden = true }
                        selected = nil
                    }
                } label: {
                    Label("隐藏此键", systemImage: "eye.slash")
                        .font(Theme.Typography.callout.weight(.medium))
                }
                .buttonStyle(TextButtonStyle(tint: Theme.Palette.textPrimary))
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, 10)
            .glass(cornerRadius: 20)
            .frame(maxWidth: 720)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            let hidden = scheme.elements.filter(\.hidden)
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "hand.draw")
                    .foregroundStyle(Theme.Palette.textSecondary)
                Text("拖动移动，双指缩放，点按选中后可调整")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Palette.textSecondary)
                if !hidden.isEmpty {
                    Rectangle().fill(Theme.Palette.hairlineStrong).frame(width: 0.5, height: 16)
                    Text("已隐藏").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.textTertiary)
                    ForEach(hidden) { el in
                        Button {
                            withAnimation(Theme.Motion.spring) { update(el.kind) { $0.hidden = false } }
                        } label: {
                            Text(el.kind.displayName)
                                .font(Theme.Typography.captionStrong)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .glassCapsule()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, 10)
            .glassCapsule()
            .transition(.opacity)
        }
    }

    private func sliderItem(icon: String, value: Binding<Double>, range: ClosedRange<Double>, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
            Slider(value: value, in: range).tint(Theme.Palette.accent).frame(width: 130)
            Text(verbatim: text)
                .font(Theme.Typography.mono(12))
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func saveIfNeeded() {
        guard dirty else { return }
        store.update(scheme)
        dirty = false
    }
}

private struct GridPattern: Shape {
    var spacing: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x: CGFloat = 0
        while x <= rect.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: rect.height)); x += spacing * 4 }
        var y: CGFloat = 0
        while y <= rect.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: rect.width, y: y)); y += spacing * 4 }
        return p
    }
}

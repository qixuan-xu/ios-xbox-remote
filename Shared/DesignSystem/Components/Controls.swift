import SwiftUI

// MARK: - 状态胶囊

struct StatusPill: View {
    var status: ConsoleStatus
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                if status == .online && !reduceMotion {
                    Circle()
                        .fill(status.color.opacity(0.5))
                        .frame(width: 7, height: 7)
                        .scaleEffect(pulse ? 2.4 : 1)
                        .opacity(pulse ? 0 : 0.8)
                }
                Circle()
                    .fill(status.color)
                    .frame(width: 7, height: 7)
            }
            Text(status.label)
                .font(Theme.Typography.captionStrong)
                .foregroundStyle(Theme.Palette.textPrimary.opacity(0.85))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassCapsule()
        .onAppear {
            guard status == .online, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { pulse = true }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 分段控件

struct SegmentedPicker<Value: Hashable>: View {
    var options: [(Value, LocalizedStringKey)]
    @Binding var selection: Value
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let isSelected = option.0 == selection
                Button {
                    Haptics.selection()
                    withAnimation(Theme.Motion.snappy) { selection = option.0 }
                } label: {
                    Text(option.1)
                        .font(Theme.Typography.captionStrong)
                        .foregroundStyle(isSelected ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Color.white.opacity(0.14))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                                    )
                                    .matchedGeometryEffect(id: "segment", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.25))
        )
    }
}

// MARK: - 设置行

struct SettingsGroup<Content: View>: View {
    var title: LocalizedStringKey?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let title {
                Text(title)
                    .overlineStyle()
                    .padding(.leading, Theme.Spacing.m)
            }
            VStack(spacing: 0) {
                content
            }
            .glass(cornerRadius: Theme.Radius.card - 4)
        }
    }
}

/// 设置组内的一行，自带底部发丝线（最后一行传 showsDivider: false）
struct SettingsRow<Trailing: View>: View {
    var icon: String?
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var showsDivider: Bool = true
    var titleColor: Color = Theme.Palette.textPrimary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.s) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(width: 24)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Typography.body)
                        .foregroundStyle(titleColor)
                    if let subtitle {
                        Text(subtitle)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
                Spacer(minLength: Theme.Spacing.s)
                trailing
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 13)
            if showsDivider {
                Hairline().padding(.leading, icon == nil ? Theme.Spacing.m : 52)
            }
        }
    }
}

struct ToggleRow: View {
    var icon: String?
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @Binding var isOn: Bool
    var showsDivider: Bool = true

    var body: some View {
        SettingsRow(icon: icon, title: title, subtitle: subtitle, showsDivider: showsDivider) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Theme.Palette.accent)
        }
    }
}

struct SliderRow: View {
    var icon: String?
    var title: LocalizedStringKey
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double? = nil
    var format: (Double) -> String
    var showsDivider: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.s) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .frame(width: 24)
                    }
                    Text(title)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Spacer()
                    Text(format(value))
                        .font(Theme.Typography.mono(15))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .contentTransition(.numericText())
                        .animation(Theme.Motion.snappy, value: value)
                }
                Group {
                    if let step {
                        Slider(value: $value, in: range, step: step)
                    } else {
                        Slider(value: $value, in: range)
                    }
                }
                .tint(Theme.Palette.accent)
                .padding(.leading, icon == nil ? 0 : 36)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 12)
            if showsDivider {
                Hairline().padding(.leading, icon == nil ? Theme.Spacing.m : 52)
            }
        }
    }
}

struct NavigationRowLabel: View {
    var icon: String?
    var title: LocalizedStringKey
    var value: String? = nil
    var showsDivider: Bool = true

    var body: some View {
        SettingsRow(icon: icon, title: title, showsDivider: showsDivider) {
            HStack(spacing: 6) {
                if let value {
                    Text(value)
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - 电量环

struct BatteryRing: View {
    var level: Float?   // 0...1，nil 表示未知
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.14), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: CGFloat(level ?? 0))
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: size, height: size)
            if let level {
                Text(verbatim: "\(Int((level * 100).rounded()))%")
                    .font(Theme.Typography.mono(13))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .contentTransition(.numericText())
            }
        }
        .animation(Theme.Motion.spring, value: level)
        .accessibilityLabel(Text(level.map { "电量 \(Int($0 * 100))%" } ?? "电量未知"))
    }

    private var color: Color {
        guard let level else { return Theme.Palette.neutral }
        if level < 0.15 { return Theme.Palette.danger }
        if level < 0.35 { return Theme.Palette.amber }
        return Theme.Palette.accent
    }
}

// MARK: - 信号格

struct SignalBars: View {
    var quality: Int   // 0...3

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(i < quality ? color : Color.white.opacity(0.18))
                    .frame(width: 3, height: CGFloat(5 + i * 4))
            }
        }
        .animation(Theme.Motion.spring, value: quality)
    }

    private var color: Color {
        switch quality {
        case 3: return Theme.Palette.accent
        case 2: return Theme.Palette.amber
        default: return Theme.Palette.danger
        }
    }
}

// MARK: - 骨架屏微光

struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.08), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: phase * geo.size.width * 1.4)
                    .blendMode(.plusLighter)
                }
                .mask(content)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}

// MARK: - 细环加载指示器

struct ThinRingSpinner: View {
    var size: CGFloat = 28
    var lineWidth: CGFloat = 2
    var tint: Color = Theme.Palette.textPrimary
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(rotation))
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { rotation = 360 }
        }
    }
}

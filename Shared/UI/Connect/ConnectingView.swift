import SwiftUI

/// 连接页：主机线稿居中 + 细圆环进度 + 竖向时间线
struct ConnectingView: View {
    @ObservedObject var stream: StreamController
    @EnvironmentObject private var app: AppState
    @Environment(\.heroNamespace) private var heroNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var showHelp = false

    private var failure: (StreamError, ConnectStep)? {
        if case .failed(let error, let step) = stream.phase { return (error, step) }
        return nil
    }

    private var progress: CGFloat {
        if failure != nil { return CGFloat(stream.stepDurations.count) / 4 }
        let done = CGFloat(stream.stepDurations.count)
        return min(1, (done + 0.5) / CGFloat(ConnectStep.allCases.count))
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                Color.black.opacity(appeared ? 0.92 : 0).ignoresSafeArea()

                Group {
                    if landscape {
                        HStack(spacing: Theme.Spacing.xxl) {
                            hero.frame(maxWidth: geo.size.width * 0.4)
                            details.frame(maxWidth: 380)
                        }
                    } else {
                        VStack(spacing: Theme.Spacing.xl) {
                            Spacer(minLength: Theme.Spacing.l)
                            hero
                            details
                            Spacer(minLength: Theme.Spacing.l)
                        }
                    }
                }
                .padding(Theme.Spacing.l)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { withAnimation(Theme.Motion.adaptive(reduceMotion)) { appeared = true } }
        .sheet(isPresented: $showHelp) {
            SetupGuideView()
                #if os(macOS)
                .frame(width: 560, height: 620)
                #endif
        }
    }

    // MARK: 主机 + 圆环

    private var hero: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: 2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(failure == nil ? Theme.Palette.accent : Theme.Palette.danger,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Theme.Motion.spring, value: progress)
            if failure == nil {
                ThinRingSpinner(size: 230, lineWidth: 1, tint: Theme.Palette.accent.opacity(0.5))
                    .opacity(0.6)
            }
            Circle()
                .fill(RadialGradient(colors: [(failure == nil ? Theme.Palette.accent : Theme.Palette.neutral).opacity(0.16), .clear],
                                     center: .center, startRadius: 0, endRadius: 120))
            if let title = stream.cloudTitle {
                CloudPoster(title: title)
                    .frame(width: 100, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
                    .saturation(failure == nil ? 1 : 0.2)
                    .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
            } else {
                ConsoleSilhouette(kind: stream.console.kind, lineWidth: 1.4, dimmed: failure != nil)
                    .frame(height: 120)
                    .hero("console-\(stream.console.id)", in: heroNamespace)
            }
        }
        .frame(width: 230, height: 230)
        .accessibilityHidden(true)
    }

    // MARK: 时间线 + 按钮

    private var details: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: 4) {
                Text(stream.console.name).titleStyle()
                Text(failure == nil ? LocalizedStringKey("正在连接") : LocalizedStringKey("连接失败"))
                    .font(Theme.Typography.callout)
                    .foregroundStyle(failure == nil ? Theme.Palette.textSecondary : Theme.Palette.danger)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(ConnectStep.allCases) { step in
                    TimelineRow(step: step,
                                state: state(for: step),
                                duration: stream.stepDurations[step],
                                isLast: step == ConnectStep.allCases.last)
                }
            }

            if let failure {
                let error = failure.0
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(error.localizedDescription)
                        .font(Theme.Typography.callout.weight(.medium))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let hint = error.helpHint {
                        Text(hint)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Theme.Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass(cornerRadius: 16)
                .transition(.opacity.combined(with: .move(edge: .bottom)))

                VStack(spacing: Theme.Spacing.xs) {
                    Button("重试") { stream.retry() }
                        .buttonStyle(PrimaryButtonStyle())
                    HStack {
                        Button("查看帮助") { showHelp = true }
                            .buttonStyle(TextButtonStyle())
                        Spacer()
                        Button("返回") { app.closeStream() }
                            .buttonStyle(TextButtonStyle())
                    }
                }
            } else {
                Button("取消") { app.closeStream() }
                    .buttonStyle(GhostButtonStyle())
            }
        }
        .animation(Theme.Motion.spring, value: stream.phase)
    }

    private func state(for step: ConnectStep) -> TimelineRow.State {
        if let failure {
            if step == failure.1 { return .failed }
            return stream.stepDurations[step] != nil ? .done : .pending
        }
        if stream.stepDurations[step] != nil { return .done }
        if case .connecting(let current) = stream.phase, current == step { return .active }
        return .pending
    }
}

private struct TimelineRow: View {
    enum State { case pending, active, done, failed }
    var step: ConnectStep
    var state: State
    var duration: TimeInterval?
    var isLast: Bool

    @SwiftUI.State private var pulse = false
    @SwiftUI.State private var checkTrim: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            VStack(spacing: 0) {
                node
                    .frame(width: 22, height: 22)
                if !isLast {
                    Rectangle()
                        .fill(state == .done ? Theme.Palette.accent.opacity(0.6) : Theme.Palette.hairlineStrong)
                        .frame(width: 1, height: 26)
                }
            }
            Text(step.title)
                .font(Theme.Typography.body.weight(state == .active ? .semibold : .regular))
                .foregroundStyle(textColor)
                .padding(.top, 1)
            Spacer()
            if let duration {
                Text(String(format: "%.1fs", duration))
                    .font(Theme.Typography.mono(13))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .transition(.opacity)
                    .padding(.top, 3)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var textColor: Color {
        switch state {
        case .pending: return Theme.Palette.textTertiary
        case .active: return Theme.Palette.textPrimary
        case .done: return Theme.Palette.textSecondary
        case .failed: return Theme.Palette.danger
        }
    }

    @ViewBuilder
    private var node: some View {
        switch state {
        case .pending:
            Circle().strokeBorder(Theme.Palette.hairlineStrong, lineWidth: 1)
                .frame(width: 12, height: 12)
        case .active:
            ZStack {
                Circle()
                    .fill(Theme.Palette.accent.opacity(0.25))
                    .scaleEffect(pulse ? 1.6 : 0.8)
                    .opacity(pulse ? 0 : 1)
                Circle().fill(Theme.Palette.accent).frame(width: 10, height: 10)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { pulse = true }
            }
        case .done:
            ZStack {
                Circle().fill(Theme.Palette.accent)
                CheckShape()
                    .trim(from: 0, to: checkTrim)
                    .stroke(Color.black.opacity(0.85), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .padding(6)
            }
            .frame(width: 18, height: 18)
            .onAppear { withAnimation(.easeOut(duration: 0.35)) { checkTrim = 1 } }
        case .failed:
            ZStack {
                Circle().fill(Theme.Palette.danger)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(Color.black.opacity(0.8))
            }
            .frame(width: 18, height: 18)
        }
    }
}

private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.08))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.1))
        return p
    }
}

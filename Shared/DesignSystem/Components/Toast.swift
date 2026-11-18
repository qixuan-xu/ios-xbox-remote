import SwiftUI

/// 顶部下滑的玻璃提示条。替代系统 Alert，用于错误、状态切换等。
struct ToastMessage: Identifiable, Equatable {
    enum Style: Equatable { case info, success, warning, error }

    let id = UUID()
    var icon: String
    var text: String
    var style: Style = .info
    var actionTitle: String? = nil
    var duration: TimeInterval = 2.4
    var action: (() -> Void)? = nil

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool { lhs.id == rhs.id }

    var tint: Color {
        switch style {
        case .info: return Theme.Palette.textPrimary
        case .success: return Theme.Palette.accent
        case .warning: return Theme.Palette.amber
        case .error: return Theme.Palette.danger
        }
    }
}

struct ToastView: View {
    var toast: ToastMessage
    var onAction: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: toast.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(toast.tint)
                .frame(width: 22)
            Text(toast.text)
                .font(Theme.Typography.callout.weight(.medium))
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let title = toast.actionTitle {
                Spacer(minLength: Theme.Spacing.xs)
                Button(title, action: onAction)
                    .font(Theme.Typography.captionStrong)
                    .foregroundStyle(Theme.Palette.accent)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, 12)
        .glass(cornerRadius: 18)
        .cardShadow()
        .frame(maxWidth: 480)
    }
}

struct ToastHost: ViewModifier {
    @Binding var toast: ToastMessage?
    @State private var dismissTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                ZStack {
                    if let toast {
                        ToastView(toast: toast) {
                            toast.action?()
                            dismiss()
                        }
                        .padding(.horizontal, Theme.Spacing.m)
                        .padding(.top, Theme.Spacing.xs)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        .gesture(DragGesture(minimumDistance: 8).onEnded { value in
                            if value.translation.height < -10 { dismiss() }
                        })
                        .id(toast.id)
                    }
                }
                .animation(Theme.Motion.spring, value: toast)
            }
            .onChange(of: toast) { newValue in
                dismissTask?.cancel()
                guard let newValue else { return }
                let duration = newValue.actionTitle == nil ? newValue.duration : max(newValue.duration, 5)
                dismissTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    if toast?.id == newValue.id { toast = nil }
                }
            }
    }

    private func dismiss() {
        withAnimation(Theme.Motion.spring) { toast = nil }
    }
}

extension View {
    func toastHost(_ toast: Binding<ToastMessage?>) -> some View {
        modifier(ToastHost(toast: toast))
    }
}

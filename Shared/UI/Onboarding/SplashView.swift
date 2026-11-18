import SwiftUI

/// 启动页：标志 + 从中间向两侧伸展的细进度线
struct SplashView: View {
    @State private var lineProgress: CGFloat = 0
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            AppMark(size: 96)
                .scaleEffect(appeared ? 1 : 0.92)
                .opacity(appeared ? 1 : 0)

            Capsule()
                .fill(
                    LinearGradient(colors: [.clear, Theme.Palette.accent, .clear],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .frame(width: 140 * lineProgress, height: 2)
                .frame(width: 140)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(Theme.Motion.adaptive(reduceMotion)) { appeared = true }
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                lineProgress = 1
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("正在启动"))
    }
}

#Preview {
    ZStack {
        AmbientBackground()
        SplashView()
    }
}

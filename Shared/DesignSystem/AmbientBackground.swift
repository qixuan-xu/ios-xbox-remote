import SwiftUI

/// 缓慢流动的深色背景：近黑底色上叠加两到三团低饱和光斑，约 40 秒一个周期。
/// 「减弱动态效果」开启时保持静止。
struct AmbientBackground: View {
    var intensity: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.Palette.background
            if reduceMotion {
                canvas(time: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
                    canvas(time: context.date.timeIntervalSinceReferenceDate)
                }
            }
            // 轻微暗角，让内容区更聚焦
            RadialGradient(
                colors: [.clear, Color.black.opacity(0.55)],
                center: .center,
                startRadius: 200,
                endRadius: 900
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func canvas(time: TimeInterval) -> some View {
        Canvas { context, size in
            let period = 40.0
            let t = (time.truncatingRemainder(dividingBy: period)) / period * 2 * .pi
            let w = size.width
            let h = size.height
            let base = max(w, h)

            let blobs: [(Color, CGPoint, CGFloat)] = [
                (Theme.Palette.ambientGreen,
                 CGPoint(x: w * (0.25 + 0.10 * cos(t)), y: h * (0.20 + 0.08 * sin(t * 1.3))),
                 base * 0.65),
                (Theme.Palette.ambientGraphite,
                 CGPoint(x: w * (0.80 + 0.08 * sin(t * 0.8)), y: h * (0.55 + 0.10 * cos(t))),
                 base * 0.70),
                (Theme.Palette.ambientTeal,
                 CGPoint(x: w * (0.40 + 0.12 * sin(t * 0.6 + 1)), y: h * (0.95 + 0.05 * cos(t * 1.1))),
                 base * 0.55)
            ]

            context.addFilter(.blur(radius: base * 0.12))
            for (color, center, diameter) in blobs {
                let rect = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
                context.opacity = 0.9 * intensity
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
    }
}

#Preview {
    AmbientBackground()
}

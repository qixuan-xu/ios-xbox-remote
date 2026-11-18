import UIKit

/// 界面触感反馈（iOS）
enum Haptics {
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    /// 用户可在设置里关闭按键触感（只影响串流页屏幕按键）
    static var controlsEnabled = true

    static func selection() { selectionGenerator.selectionChanged() }
    static func impact() { mediumGenerator.impactOccurred() }
    static func light() { lightGenerator.impactOccurred(intensity: 0.7) }
    static func success() { notificationGenerator.notificationOccurred(.success) }
    static func warning() { notificationGenerator.notificationOccurred(.warning) }
    static func error() { notificationGenerator.notificationOccurred(.error) }

    /// 屏幕按键按下
    static func controlPress() {
        guard controlsEnabled else { return }
        rigidGenerator.impactOccurred(intensity: 0.55)
    }

    static func prepareControls() {
        rigidGenerator.prepare()
    }
}

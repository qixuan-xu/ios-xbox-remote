import AppKit

/// 界面触感反馈（Mac：触控板力反馈，没有则忽略）
enum Haptics {
    static var controlsEnabled = true

    private static var performer: NSHapticFeedbackPerformer { NSHapticFeedbackManager.defaultPerformer }

    static func selection() { performer.perform(.alignment, performanceTime: .now) }
    static func impact() { performer.perform(.generic, performanceTime: .now) }
    static func light() {}
    static func success() { performer.perform(.levelChange, performanceTime: .now) }
    static func warning() { performer.perform(.generic, performanceTime: .now) }
    static func error() { performer.perform(.generic, performanceTime: .now) }
    static func controlPress() {}
    static func prepareControls() {}
}

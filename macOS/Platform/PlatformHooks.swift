import AppKit

/// 进入 / 退出串流时的平台处理（Mac）
@MainActor
enum PlatformHooks {
    private static var activity: NSObjectProtocol?

    private static var keyMonitor: Any?

    /// 串流时吞掉键盘事件，避免系统提示音（⌘ 组合键照常交给菜单）
    static func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            if event.modifierFlags.contains(.command) { return event }
            return KeyEventGate.swallow ? nil : event
        }
    }

    static func enterStream() {
        installKeyMonitorIfNeeded()
        KeyEventGate.swallow = true
        // 串流时阻止系统睡眠
        activity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled, .userInitiated],
                                                         reason: "Streaming")
        ControllerManager.shared.keyboardInputEnabled = true
    }

    static func exitStream() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        KeyEventGate.swallow = false
        ControllerManager.shared.keyboardInputEnabled = false
        NSCursor.unhide()
        if let window = NSApp.keyWindow, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }

    static func toggleFullScreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }

    /// 鼠标静止时隐藏光标，移动后自动出现
    static func scheduleCursorHide() {
        NSCursor.setHiddenUntilMouseMoves(true)
    }
}

/// 是否拦截键盘事件（事件监视器在主线程同步调用）
enum KeyEventGate {
    static var swallow = false
}

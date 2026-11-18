import UIKit
import SwiftUI

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}

/// 控制界面方向：主页跟随设备，串流时锁定横屏
@MainActor
enum OrientationLock {
    static var mask: UIInterfaceOrientationMask = UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown

    static func set(_ newMask: UIInterfaceOrientationMask) {
        mask = newMask
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        else { return }
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: newMask)) { _ in }
    }
}

/// 进入 / 退出串流时的平台处理
@MainActor
enum PlatformHooks {
    static func enterStream() {
        OrientationLock.set(.landscape)
        UIApplication.shared.isIdleTimerDisabled = true
        Haptics.prepareControls()
        // iPad 外接键盘也可以用键位映射
        ControllerManager.shared.keyboardInputEnabled = true
    }

    static func exitStream() {
        OrientationLock.set(UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown)
        UIApplication.shared.isIdleTimerDisabled = false
        ControllerManager.shared.keyboardInputEnabled = false
    }

    static func toggleFullScreen() {}
    static func scheduleCursorHide() {}
}

import Foundation

/// 调试启动参数（只在 DEBUG 生效），用于自动截图：
///   -demo                 直接进入演示模式
///   -screen <name>        跳到指定页面：welcome / home / settings / connecting / stream / menu / editor / guide
enum DebugLaunch {
    static let screen: String? = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-screen"), i + 1 < args.count { return args[i + 1] }
        #endif
        return nil
    }()

    static let demo: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-demo")
        #else
        return false
        #endif
    }()

    static func `is`(_ name: String) -> Bool { screen == name }
}

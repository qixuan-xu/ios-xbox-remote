import Foundation

/// 调试日志：只在调试版（Debug）输出到 Xcode 控制台；Release 版完全不打印，
/// 避免把服务器返回内容、网络地址等写进系统日志。
@inline(__always)
func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}

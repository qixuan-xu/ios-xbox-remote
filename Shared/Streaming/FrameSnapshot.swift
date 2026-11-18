import Foundation
import CoreImage
import WebRTC

/// 把 WebRTC 视频帧转成 CGImage（截图用）
enum FrameSnapshot {
    private static let context = CIContext(options: nil)

    static func cgImage(from frame: RTCVideoFrame) -> CGImage? {
        guard let buffer = frame.buffer as? RTCCVPixelBuffer else { return nil }
        var image = CIImage(cvPixelBuffer: buffer.pixelBuffer)
        switch frame.rotation {
        case ._90: image = image.oriented(.right)
        case ._180: image = image.oriented(.down)
        case ._270: image = image.oriented(.left)
        default: break
        }
        return context.createCGImage(image, from: image.extent)
    }
}

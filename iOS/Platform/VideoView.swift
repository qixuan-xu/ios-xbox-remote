import SwiftUI
import WebRTC
import Photos

/// 视频渲染（Metal）。帧由 FrameTap 转发进来。
struct VideoView: UIViewRepresentable {
    var frameTap: FrameTap?
    var fillMode: VideoFillMode

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        view.backgroundColor = .black
        view.videoContentMode = fillMode == .fill ? .scaleAspectFill : .scaleAspectFit
        view.clipsToBounds = true
        frameTap?.target = view
        return view
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        uiView.videoContentMode = fillMode == .fill ? .scaleAspectFill : .scaleAspectFit
        if frameTap?.target !== uiView { frameTap?.target = uiView }
    }
}

/// 截图保存到相册
enum ScreenshotSaver {
    static func save(_ image: CGImage) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }
        let uiImage = UIImage(cgImage: image)
        return await withCheckedContinuation { cont in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: uiImage)
            }, completionHandler: { success, _ in
                cont.resume(returning: success)
            })
        }
    }
}

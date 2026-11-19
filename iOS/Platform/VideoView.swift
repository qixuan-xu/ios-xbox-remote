import SwiftUI
import WebRTC
import Photos

/// 视频渲染（iPhone），实际绘制见 Shared/Platform/SampleBufferVideoView.swift
struct VideoView: UIViewRepresentable {
    var frameTap: FrameTap?
    var fillMode: VideoFillMode
    var pacing: VideoPacing = .balanced

    func makeUIView(context: Context) -> SampleBufferVideoView {
        let view = SampleBufferVideoView(frame: .zero)
        view.fill = fillMode == .fill
        view.pacing = pacing
        frameTap?.target = view
        return view
    }

    func updateUIView(_ uiView: SampleBufferVideoView, context: Context) {
        uiView.fill = fillMode == .fill
        if uiView.pacing != pacing { uiView.pacing = pacing }
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

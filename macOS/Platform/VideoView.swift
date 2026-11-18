import SwiftUI
import WebRTC

/// 视频渲染（Metal）。Mac 版用 SwiftUI 控制 16:9 比例。
struct VideoView: View {
    var frameTap: FrameTap?
    var fillMode: VideoFillMode

    var body: some View {
        MetalVideoView(frameTap: frameTap)
            .aspectRatio(16 / 9, contentMode: fillMode == .fill ? .fill : .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }
}

private struct MetalVideoView: NSViewRepresentable {
    var frameTap: FrameTap?

    func makeNSView(context: Context) -> RTCMTLNSVideoView {
        let view = RTCMTLNSVideoView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        frameTap?.target = view
        return view
    }

    func updateNSView(_ nsView: RTCMTLNSVideoView, context: Context) {
        if frameTap?.target !== nsView { frameTap?.target = nsView }
    }
}

/// 截图保存到「图片」文件夹
enum ScreenshotSaver {
    static func save(_ image: CGImage) async -> Bool {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let name = "Xbox Remote \(formatter.string(from: Date())).png"
        guard let dir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first else { return false }
        do {
            try data.write(to: dir.appendingPathComponent(name))
            return true
        } catch {
            return false
        }
    }
}

import SwiftUI
import AppKit
import AVFoundation
import CoreMedia
import WebRTC

/// 视频渲染（Mac）。
/// stasel/WebRTC 的 macOS 版本没有导出 RTCMTLNSVideoView，这里自己实现：
/// 硬件解码出来的 CVPixelBuffer 直接包成 CMSampleBuffer 交给 AVSampleBufferDisplayLayer。
struct VideoView: NSViewRepresentable {
    var frameTap: FrameTap?
    var fillMode: VideoFillMode

    func makeNSView(context: Context) -> SampleBufferVideoView {
        let view = SampleBufferVideoView(frame: .zero)
        view.fill = fillMode == .fill
        frameTap?.target = view
        return view
    }

    func updateNSView(_ nsView: SampleBufferVideoView, context: Context) {
        nsView.fill = fillMode == .fill
        if frameTap?.target !== nsView { frameTap?.target = nsView }
    }
}

final class SampleBufferVideoView: NSView, RTCVideoRenderer {
    private let displayLayer = AVSampleBufferDisplayLayer()
    private let renderQueue = DispatchQueue(label: "xr.video.render", qos: .userInteractive)

    var fill = false {
        didSet { displayLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(displayLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        CATransaction.commit()
    }

    // MARK: RTCVideoRenderer

    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame, let buffer = frame.buffer as? RTCCVPixelBuffer else { return }
        guard let sample = Self.makeSampleBuffer(buffer.pixelBuffer) else { return }
        // 不等主线程：在专用串行队列上直接送显，界面忙时也不掉帧
        let layer = displayLayer
        renderQueue.async {
            if layer.status == .failed { layer.flush() }
            layer.enqueue(sample)
        }
    }

    private static func makeSampleBuffer(_ pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                           imageBuffer: pixelBuffer,
                                                           formatDescriptionOut: &format) == noErr,
              let format else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid,
                                        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                       imageBuffer: pixelBuffer,
                                                       formatDescription: format,
                                                       sampleTiming: &timing,
                                                       sampleBufferOut: &sample) == noErr,
              let sample else { return nil }
        // 立即显示，不按时间戳排队
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary] {
            attachments.first?[kCMSampleAttachmentKey_DisplayImmediately] = true
        }
        return sample
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

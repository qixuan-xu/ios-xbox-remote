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
    var pacing: VideoPacing = .balanced

    func makeNSView(context: Context) -> SampleBufferVideoView {
        let view = SampleBufferVideoView(frame: .zero)
        view.fill = fillMode == .fill
        view.pacing = pacing
        frameTap?.target = view
        return view
    }

    func updateNSView(_ nsView: SampleBufferVideoView, context: Context) {
        nsView.fill = fillMode == .fill
        if nsView.pacing != pacing { nsView.pacing = pacing }
        if frameTap?.target !== nsView { frameTap?.target = nsView }
    }
}

final class SampleBufferVideoView: NSView, RTCVideoRenderer {
    private let displayLayer = AVSampleBufferDisplayLayer()
    private let renderQueue = DispatchQueue(label: "xr.video.render", qos: .userInteractive)

    // 帧节奏：用主机发出画面时的 RTP 时间戳（90kHz）作为显示时间，配合 controlTimebase 匀速显示，
    // 避免网络到达时快时慢造成的「一顿一顿」。缓冲约 1 帧。
    private var timebase: CMTimebase?
    private var lastRTP: UInt32?
    private var rtpTotal: Int64 = 0
    private var needsResync = true
    /// 画面模式：切换时重新对齐时间基准
    var pacing: VideoPacing = .balanced {
        didSet { renderQueue.async { [weak self] in self?.needsResync = true } }
    }
    private var bufferDelay: CMTime { CMTime(value: CMTimeValue(pacing.bufferMilliseconds), timescale: 1000) }
    private static let lateLimit = CMTime(value: 60, timescale: 1000)
    private static let earlyLimit = CMTime(value: 200, timescale: 1000)

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
        var tb: CMTimebase?
        if CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault,
                                           sourceClock: CMClockGetHostTimeClock(),
                                           timebaseOut: &tb) == noErr, let tb {
            CMTimebaseSetRate(tb, rate: 0)
            displayLayer.controlTimebase = tb
            timebase = tb
        }
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
        let pixelBuffer = buffer.pixelBuffer
        let rtp = UInt32(bitPattern: frame.timeStamp)
        // 不等主线程：在专用串行队列上处理时间戳并送显
        renderQueue.async { [weak self] in
            guard let self else { return }
            let layer = self.displayLayer
            if layer.status == .failed { layer.flush(); self.needsResync = true }

            // RTP 时间戳会回绕，展开成单调递增
            if let last = self.lastRTP {
                self.rtpTotal += Int64(Int32(bitPattern: rtp &- last))
            }
            self.lastRTP = rtp
            let pts = CMTime(value: self.rtpTotal, timescale: 90_000)

            if let tb = self.timebase {
                let now = CMTimebaseGetTime(tb)
                let tooLate = CMTimeCompare(pts, CMTimeSubtract(now, Self.lateLimit)) < 0
                let tooEarly = CMTimeCompare(pts, CMTimeAdd(now, Self.earlyLimit)) > 0
                if self.needsResync || tooLate || tooEarly {
                    CMTimebaseSetTime(tb, time: CMTimeSubtract(pts, self.bufferDelay))
                    CMTimebaseSetRate(tb, rate: 1)
                    self.needsResync = false
                }
            }
            // 低延迟模式或没有时间基准：收到就显示
            let usePacing = self.timebase != nil && self.pacing != .lowLatency
            guard let sample = Self.makeSampleBuffer(pixelBuffer, pts: usePacing ? pts : nil) else { return }
            layer.enqueue(sample)
        }
    }

    private static func makeSampleBuffer(_ pixelBuffer: CVPixelBuffer, pts: CMTime?) -> CMSampleBuffer? {
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                           imageBuffer: pixelBuffer,
                                                           formatDescriptionOut: &format) == noErr,
              let format else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid,
                                        presentationTimeStamp: pts ?? CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                       imageBuffer: pixelBuffer,
                                                       formatDescription: format,
                                                       sampleTiming: &timing,
                                                       sampleBufferOut: &sample) == noErr,
              let sample else { return nil }
        // 没有时间基准时退回「立即显示」
        if pts == nil, let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary] {
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

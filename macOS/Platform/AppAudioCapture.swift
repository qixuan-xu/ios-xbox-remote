import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia

/// 用 ScreenCaptureKit 只捕获本 App 自己播放的声音（也就是游戏声音），供字幕识别使用。
/// stasel/WebRTC 的 macOS 版本没有 RTCAudioDevice，拿不到解码后的音频，所以走这条路。
/// 第一次使用时系统会请求「录屏与系统录音」权限；这里只取音频，视频设成 2×2、每秒 1 帧并丢弃。
final class AppAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    enum CaptureError: LocalizedError {
        case permissionDenied
        case appNotFound

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return String(localized: "需要「录屏与系统录音」权限才能听到游戏声音，请在系统设置里允许 XboxRemote 后重新打开字幕")
            case .appNotFound:
                return String(localized: "没有找到本 App 的音频来源")
            }
        }
    }

    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "xr.caption.audio", qos: .userInitiated)

    func start() async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            CaptionLog.log("获取可捕获内容失败（多半是没有录屏权限）: \(error.localizedDescription)")
            throw CaptureError.permissionDenied
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        guard let app = content.applications.first(where: { $0.processID == pid }),
              let display = content.displays.first else {
            throw CaptureError.appNotFound
        }

        let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = false
        config.sampleRate = 16_000
        config.channelCount = 1
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.queueDepth = 3

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        // 加一个视频输出并直接丢弃，避免系统不停打印「找不到输出」
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
        CaptionLog.log("开始捕获 App 声音")
    }

    func stop() {
        guard let stream else { return }
        self.stream = nil
        Task { try? await stream.stopCapture() }
        CaptionLog.log("停止捕获 App 声音")
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, let pcm = Self.pcmBuffer(from: sampleBuffer) else { return }
        onBuffer?(pcm)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        CaptionLog.log("声音捕获停止: \(error.localizedDescription)")
    }

    /// CMSampleBuffer → AVAudioPCMBuffer
    static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let format = AVAudioFormat(streamDescription: asbd) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        pcm.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frames),
                                                                  into: pcm.mutableAudioBufferList)
        return status == noErr ? pcm : nil
    }
}

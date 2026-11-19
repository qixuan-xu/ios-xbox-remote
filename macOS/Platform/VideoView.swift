import SwiftUI
import AppKit
import AVFoundation
import CoreMedia
import WebRTC

/// 视频渲染（Mac），实际绘制见 Shared/Platform/SampleBufferVideoView.swift
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

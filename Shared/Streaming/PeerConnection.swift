import Foundation
import QuartzCore
import WebRTC

/// 数据通道的封装：统一发送 / 接收，回调在主线程以外触发。
final class DataChannel: NSObject, RTCDataChannelDelegate {
    let label: String
    let channel: RTCDataChannel
    var onOpen: (() -> Void)?
    var onMessage: ((Data) -> Void)?
    var onClose: (() -> Void)?

    init(channel: RTCDataChannel) {
        self.channel = channel
        self.label = channel.label
        super.init()
        channel.delegate = self
    }

    var isOpen: Bool { channel.readyState == .open }

    /// 参考实现把字符串用 TextEncoder 编码后以二进制发送，这里保持一致
    func send(text: String) {
        send(data: Data(text.utf8))
    }

    func send(data: Data) {
        guard isOpen else { return }
        channel.sendData(RTCDataBuffer(data: data, isBinary: true))
    }

    func close() {
        channel.delegate = nil
        channel.close()
    }

    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        print("[Stream] 数据通道 \(label) 状态: \(dataChannel.readyState.rawValue) (0连接中 1打开 2关闭中 3关闭)")
        switch dataChannel.readyState {
        case .open: onOpen?()
        case .closed: onClose?()
        default: break
        }
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        onMessage?(buffer.data)
    }
}

/// 视频帧拦截：把帧转给真正的渲染视图，同时记录元数据、帧率和最后一帧（截图用）。
final class FrameTap: NSObject, RTCVideoRenderer {
    weak var target: RTCVideoRenderer? {
        didSet { if let size = lastSize { target?.setSize(size) } }
    }
    var onFirstFrame: (() -> Void)?
    var onMetadata: ((VideoMetadataFrame) -> Void)?

    private let lock = NSLock()
    private var gotFirstFrame = false
    private var lastSize: CGSize?
    private var frameTimes: [CFTimeInterval] = []
    private(set) var lastFrame: RTCVideoFrame?
    private let start = CACurrentMediaTime()

    func setSize(_ size: CGSize) {
        lastSize = size
        DispatchQueue.main.async { [weak self] in self?.target?.setSize(size) }
    }

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }
        target?.renderFrame(frame)

        let now = CACurrentMediaTime()
        let ms = UInt32(truncatingIfNeeded: Int64((now - start) * 1000))
        lock.lock()
        lastFrame = frame
        frameTimes.append(now)
        if frameTimes.count > 120 { frameTimes.removeFirst(frameTimes.count - 120) }
        let first = !gotFirstFrame
        gotFirstFrame = true
        lock.unlock()

        onMetadata?(VideoMetadataFrame(
            serverDataKey: UInt32(bitPattern: frame.timeStamp),
            firstFramePacketArrivalTimeMs: ms,
            frameSubmittedTimeMs: ms,
            frameDecodedTimeMs: ms,
            frameRenderedTimeMs: ms,
            framePacketTimeMs: ms,
            frameDateNowMs: ms
        ))
        if first {
            print("[Stream] 收到第一帧画面 \(frame.width)x\(frame.height) \(type(of: frame.buffer))")
            DispatchQueue.main.async { [weak self] in self?.onFirstFrame?() }
        }
    }

    var framesPerSecond: Double {
        lock.lock(); defer { lock.unlock() }
        guard let last = frameTimes.last else { return 0 }
        let recent = frameTimes.filter { last - $0 <= 1 }
        return Double(recent.count)
    }

    func snapshotFrame() -> RTCVideoFrame? {
        lock.lock(); defer { lock.unlock() }
        return lastFrame
    }
}

/// 一次串流的 WebRTC 连接：音视频接收 + 4 个数据通道。
final class StreamPeer: NSObject, RTCPeerConnectionDelegate {
    private static let factory: RTCPeerConnectionFactory = {
        _ = RTCInitializeSSL()
        return RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(),
                                        decoderFactory: RTCDefaultVideoDecoderFactory())
    }()

    private(set) var pc: RTCPeerConnection?
    private(set) var channels: [String: DataChannel] = [:]
    let frameTap = FrameTap()

    private(set) var videoTrack: RTCVideoTrack?
    private(set) var audioTrack: RTCAudioTrack?

    var onConnectionState: ((RTCPeerConnectionState) -> Void)?
    var onVideoTrack: ((RTCVideoTrack) -> Void)?

    private var localCandidates: [RTCIceCandidate] = []
    private var gatheringComplete = false
    private let candidateLock = NSLock()

    override init() {
        super.init()
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        // 与参考实现一致使用公共 STUN，外出（不在同一局域网）时才能穿透 NAT
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"])]
        config.continualGatheringPolicy = .gatherOnce
        config.bundlePolicy = .maxBundle
        config.rtcpMuxPolicy = .require

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let connection: RTCPeerConnection? = StreamPeer.factory.peerConnection(with: config, constraints: constraints, delegate: self)
        pc = connection

        // 音频双向（服务器期望有聊天通道），视频只收
        let audioInit = RTCRtpTransceiverInit()
        audioInit.direction = .sendRecv
        _ = connection?.addTransceiver(of: .audio, init: audioInit)
        let videoInit = RTCRtpTransceiverInit()
        videoInit.direction = .recvOnly
        _ = connection?.addTransceiver(of: .video, init: videoInit)

        // 数据通道（名字与协议版本必须与服务器一致）
        let specs: [(String, String)] = [
            ("chat", "chatV1"),
            ("control", "controlV1"),
            ("input", "1.0"),
            ("message", "messageV1")
        ]
        for (label, proto) in specs {
            let cfg = RTCDataChannelConfiguration()
            cfg.isOrdered = true
            cfg.`protocol` = proto
            let created: RTCDataChannel? = connection?.dataChannel(forLabel: label, configuration: cfg)
            if let created { channels[label] = DataChannel(channel: created) }
        }
    }

    func channel(_ label: String) -> DataChannel? { channels[label] }

    // MARK: SDP

    func createOffer(maxBitrateKbps: Int?) async throws -> String {
        guard let pc else { throw StreamError.other("WebRTC 初始化失败") }
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "true"],
            optionalConstraints: nil
        )
        let offer: RTCSessionDescription = try await withCheckedThrowingContinuation { cont in
            pc.offer(for: constraints) { sdp, error in
                if let sdp { cont.resume(returning: sdp) }
                else { cont.resume(throwing: error ?? StreamError.other("createOffer failed")) }
            }
        }
        var sdp = SdpTools.preferH264(offer.sdp)
        sdp = SdpTools.enableStereo(sdp)
        if let kbps = maxBitrateKbps, kbps > 0 {
            sdp = SdpTools.setBitrate(sdp, media: "video", kbps: kbps)
        }
        let local = RTCSessionDescription(type: .offer, sdp: sdp)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc.setLocalDescription(local) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
        return sdp
    }

    func setRemoteAnswer(_ sdp: String) async throws {
        guard let pc else { return }
        let answer = RTCSessionDescription(type: .answer, sdp: sdp)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc.setRemoteDescription(answer) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
        attachTracks()
    }

    private func attachTracks() {
        guard let pc else { return }
        for transceiver in pc.transceivers {
            print("[Stream] 收发器: \(transceiver.mediaType.rawValue) mid=\(transceiver.mid) track=\(transceiver.receiver.track?.kind ?? "nil")")
            if let video = transceiver.receiver.track as? RTCVideoTrack, videoTrack == nil {
                videoTrack = video
                video.add(frameTap)
                let track = video
                DispatchQueue.main.async { [weak self] in self?.onVideoTrack?(track) }
            } else if let audio = transceiver.receiver.track as? RTCAudioTrack, audioTrack == nil {
                audioTrack = audio
            }
        }
    }

    // MARK: ICE

    /// 等待本地候选收集完成（最多 timeout 秒）
    func gatheredCandidates(timeout: TimeInterval = 3) async -> [GssvClient.IceCandidateDTO] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            candidateLock.lock()
            let done = gatheringComplete
            candidateLock.unlock()
            if done { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        candidateLock.lock(); defer { candidateLock.unlock() }
        print("[Stream] 发送 \(localCandidates.count) 个本地候选（收集完成: \(gatheringComplete)）")
        return localCandidates.map {
            GssvClient.IceCandidateDTO(candidate: $0.sdp, sdpMid: $0.sdpMid, sdpMLineIndex: $0.sdpMLineIndex)
        }
    }

    func addRemoteCandidates(_ candidates: [GssvClient.IceCandidateDTO]) async {
        guard let pc else { return }
        for c in TeredoAddress.expand(candidates) {
            var sdp = c.candidate.trimmingCharacters(in: .whitespaces)
            if sdp.hasPrefix("a=") { sdp.removeFirst(2) }
            guard sdp.hasPrefix("candidate:") else { continue }
            let candidate = RTCIceCandidate(sdp: sdp, sdpMLineIndex: c.sdpMLineIndex ?? 0, sdpMid: c.sdpMid ?? "0")
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                pc.add(candidate) { error in
                    print("[Stream] 添加远端候选 \(error == nil ? "成功" : "失败: \(error!.localizedDescription)"): \(sdp.prefix(90))")
                    cont.resume()
                }
            }
        }
    }

    // MARK: 控制

    var audioEnabled: Bool {
        get { audioTrack?.isEnabled ?? true }
        set { audioTrack?.isEnabled = newValue }
    }

    func setVolume(_ volume: Double) {
        audioTrack?.source.volume = max(0, min(10, volume * 10))
    }

    func statistics() async -> RTCStatisticsReport? {
        guard let pc else { return nil }
        return await withCheckedContinuation { cont in
            pc.statistics { report in cont.resume(returning: report) }
        }
    }

    func close() {
        videoTrack?.remove(frameTap)
        for channel in channels.values { channel.close() }
        channels.removeAll()
        pc?.close()
        pc = nil
    }

    // MARK: RTCPeerConnectionDelegate

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("[Stream] ICE 连接状态: \(newState.rawValue) (0新建 1检查中 2已连接 3完成 4失败 5断开 6关闭)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("[Stream] 本地候选收集状态: \(newState.rawValue) (0新建 1收集中 2完成)")
        if newState == .complete {
            candidateLock.lock(); gatheringComplete = true; candidateLock.unlock()
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        candidateLock.lock(); localCandidates.append(candidate); candidateLock.unlock()
        print("[Stream] 本地候选: \(candidate.sdp.prefix(90))")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        print("[Stream] 连接状态: \(newState.rawValue) (0新建 1连接中 2已连接 3断开 4失败 5关闭)")
        let state = newState
        DispatchQueue.main.async { [weak self] in self?.onConnectionState?(state) }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        DispatchQueue.main.async { [weak self] in self?.attachTracks() }
    }
}

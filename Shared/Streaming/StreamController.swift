import Foundation
import SwiftUI
import WebRTC

/// 连接步骤（连接页时间线）
enum ConnectStep: Int, CaseIterable, Identifiable {
    case wake, session, connect, video
    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .wake: return "唤醒主机"
        case .session: return "创建会话"
        case .connect: return "建立连接"
        case .video: return "接收画面"
        }
    }
}

enum StreamPhase: Equatable {
    case connecting(ConnectStep)
    case streaming
    case reconnecting(secondsLeft: Int)
    case failed(StreamError, at: ConnectStep)
    case ended
}

struct StreamStats: Equatable {
    var latencyMs: Double?
    var fps: Double = 0
    var bitrateMbps: Double = 0
    var packetLossPercent: Double = 0
    var resolution: String?

    /// 0...3 信号格
    var quality: Int {
        guard let latency = latencyMs else { return 2 }
        if latency < 40 && packetLossPercent < 1 { return 3 }
        if latency < 90 && packetLossPercent < 4 { return 2 }
        return 1
    }
}

/// 一次串流的总控：会话 REST、WebRTC、数据通道、统计、重连。
@MainActor
final class StreamController: ObservableObject, Identifiable {
    let id = UUID()
    let console: Console
    let isDemo: Bool

    @Published private(set) var phase: StreamPhase = .connecting(.wake)
    @Published private(set) var stepDurations: [ConnectStep: TimeInterval] = [:]
    @Published private(set) var stats = StreamStats()
    @Published private(set) var videoTrack: RTCVideoTrack?
    @Published private(set) var hasFirstFrame = false
    @Published var dialog: ServerDialog?
    /// 串流页快捷菜单是否打开（Mac 菜单栏命令也会切换它）
    @Published var isMenuOpen = false
    @Published var isMuted = false { didSet { peer?.audioEnabled = !isMuted } }
    @Published var volume: Double = 1 { didSet { peer?.setVolume(volume) } }

    var onEnded: ((RecentSession) -> Void)?

    private let auth: XalAuthenticator?
    private let settings: AppSettings
    private var client: GssvClient?
    private var sessionPath: String?
    private(set) var peer: StreamPeer?
    private var channels: StreamChannels?

    private var runTask: Task<Void, Never>?
    private var keepaliveTask: Task<Void, Never>?
    private var statsTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var stepStart = Date()
    private var streamStart: Date?
    private var lastBytes: (Double, Date)?
    private var lastPackets: (received: Double, lost: Double)?

    init(console: Console, auth: XalAuthenticator?, settings: AppSettings, isDemo: Bool) {
        self.console = console
        self.auth = auth
        self.settings = settings
        self.isDemo = isDemo
    }

    var frameTap: FrameTap? { peer?.frameTap }

    var currentStep: ConnectStep {
        switch phase {
        case .connecting(let s): return s
        case .failed(_, let s): return s
        default: return .video
        }
    }

    // MARK: 生命周期

    func start() {
        runTask?.cancel()
        stepDurations = [:]
        hasFirstFrame = false
        enter(.wake)
        runTask = Task { [weak self] in
            guard let self else { return }
            if self.isDemo { await self.runDemo() } else { await self.run() }
        }
    }

    func retry() {
        teardown(stopSession: true)
        start()
    }

    func cancel() {
        teardown(stopSession: true)
        phase = .ended
    }

    func disconnect() {
        let duration = streamStart.map { Date().timeIntervalSince($0) } ?? 0
        teardown(stopSession: true)
        phase = .ended
        if duration > 5 {
            onEnded?(RecentSession(consoleId: console.id, consoleName: console.name, kind: console.kind,
                                   startedAt: streamStart ?? Date(), duration: duration))
        }
    }

    func answerDialog(confirm: Bool) {
        guard let dialog else { return }
        channels?.answerDialog(id: dialog.id, result: confirm ? 0 : 1)
        self.dialog = nil
    }

    // MARK: 真实连接流程

    private func run() async {
        do {
            guard let auth else { throw StreamError.notSignedIn }
            let creds = try await auth.streamingCredentials(offering: "xhome")
            let client = GssvClient(baseURL: creds.baseURL, token: creds.gsToken, resolution: settings.resolution)
            self.client = client

            // 1. 唤醒主机 / 发起会话
            let start = try await client.startSession(kind: .home, target: console.id)
            sessionPath = start.sessionPath
            finish(.wake); enter(.session)

            // 2. 等待会话就绪
            try await waitForProvisioned(client: client, sessionPath: start.sessionPath, auth: auth)
            startKeepalive()
            finish(.session); enter(.connect)

            // 3. WebRTC：SDP + ICE
            let peer = StreamPeer()
            self.peer = peer
            peer.audioEnabled = !isMuted
            let channels = StreamChannels(peer: peer)
            channels.dimensions = settings.resolution.dimensions
            channels.onVibration = { [weak self] report in self?.handleVibration(report) }
            channels.onServerDisconnect = { [weak self] in self?.disconnect() }
            channels.onDialog = { [weak self] dialog in self?.dialog = dialog }
            self.channels = channels

            peer.onConnectionState = { [weak self] state in self?.handleConnectionState(state) }
            peer.onVideoTrack = { [weak self] track in self?.videoTrack = track }
            peer.frameTap.onFirstFrame = { [weak self] in self?.handleFirstFrame() }

            let kbps = settings.maxBitrateMbps > 0 ? Int(settings.maxBitrateMbps * 1000) : nil
            let offer = try await peer.createOffer(maxBitrateKbps: kbps)
            try await client.sendSDPOffer(sessionPath: start.sessionPath, sdp: offer)
            let answer = try await client.waitForSDPAnswer(sessionPath: start.sessionPath)
            try await peer.setRemoteAnswer(answer)

            let local = await peer.gatheredCandidates()
            try await client.sendICECandidates(sessionPath: start.sessionPath, candidates: local)
            let remote = try await client.waitForRemoteICE(sessionPath: start.sessionPath)
            await peer.addRemoteCandidates(remote)

            // 4. 等待连接与第一帧（超时 25 秒）
            try await waitUntil(timeout: 25) { [weak self] in self?.hasFirstFrame ?? true }
            if !hasFirstFrame { throw StreamError.noVideo }
        } catch is CancellationError {
            return
        } catch let error as StreamError {
            fail(error)
        } catch let error as XboxAuthError {
            fail(.other(error.localizedDescription))
        } catch {
            fail(.other(error.localizedDescription))
        }
    }

    private func waitForProvisioned(client: GssvClient, sessionPath: String, auth: XalAuthenticator) async throws {
        let deadline = Date().addingTimeInterval(90)
        var sentConnect = false
        while Date() < deadline {
            try Task.checkCancellation()
            let state = try await client.state(sessionPath: sessionPath)
            switch state.state {
            case "Provisioned":
                return
            case "ReadyToConnect":
                if !sentConnect {
                    sentConnect = true
                    let token = try await auth.transferToken()
                    try await client.connect(sessionPath: sessionPath, userToken: token)
                }
            case "Failed":
                let code = state.errorDetails?.code ?? ""
                if code.localizedCaseInsensitiveContains("remote") { throw StreamError.remoteDisabled }
                if code.localizedCaseInsensitiveContains("offline") || code.localizedCaseInsensitiveContains("unavailable") {
                    throw StreamError.consoleOffline
                }
                throw StreamError.sessionFailed(state.errorDetails?.message ?? "")
            default:
                break
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw StreamError.timeout
    }

    private func startKeepalive() {
        keepaliveTask?.cancel()
        guard let client, let sessionPath else { return }
        keepaliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                let alive = await client.keepalive(sessionPath: sessionPath)
                if !alive { await MainActor.run { self?.fail(.sessionFailed(String(localized: "会话已结束"))) }; return }
            }
        }
    }

    private func handleFirstFrame() {
        guard !hasFirstFrame else { return }
        hasFirstFrame = true
        finish(.connect)
        finish(.video)
        streamStart = streamStart ?? Date()
        withAnimation(Theme.Motion.spring) { phase = .streaming }
        Haptics.success()
        startStats()
    }

    private func handleConnectionState(_ state: RTCPeerConnectionState) {
        switch state {
        case .connected:
            if case .connecting(.connect) = phase { finish(.connect); enter(.video) }
            if case .reconnecting = phase {
                reconnectTask?.cancel()
                withAnimation(Theme.Motion.spring) { phase = .streaming }
            }
        case .disconnected:
            if phase == .streaming { beginReconnect() }
        case .failed:
            if phase == .streaming { beginReconnect() }
            else if case .connecting = phase { fail(.iceFailed) }
        default:
            break
        }
    }

    /// 断线后 30 秒内等待恢复；超时后自动重新建立会话一次
    private func beginReconnect() {
        reconnectTask?.cancel()
        withAnimation(Theme.Motion.spring) { phase = .reconnecting(secondsLeft: 30) }
        reconnectTask = Task { [weak self] in
            for remaining in stride(from: 29, through: 0, by: -1) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self else { return }
                guard case .reconnecting = self.phase else { return }
                self.phase = .reconnecting(secondsLeft: remaining)
                if remaining == 15 {
                    // 中途尝试重建一次会话
                    self.teardown(stopSession: true, keepPhase: true)
                    self.runTask = Task { [weak self] in await self?.run() }
                }
            }
            guard let self, case .reconnecting = self.phase else { return }
            self.fail(.iceFailed)
        }
    }

    private func handleVibration(_ report: VibrationReport) {
        guard settings.controllerRumble > 0 else { return }
        ControllerManager.shared.rumbleIntensity = Float(settings.controllerRumble)
        ControllerManager.shared.rumble(report)
    }

    // MARK: 统计

    private func startStats() {
        statsTask?.cancel()
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                if self.isDemo { self.updateDemoStats() } else { await self.updateStats() }
            }
        }
    }

    private func updateStats() async {
        guard let peer, let report = await peer.statistics() else { return }
        var next = stats
        next.fps = peer.frameTap.framesPerSecond
        for (_, stat) in report.statistics {
            let values = stat.values
            if stat.type == "inbound-rtp", (values["kind"] as? String) == "video" {
                if let bytes = (values["bytesReceived"] as? NSNumber)?.doubleValue {
                    let now = Date()
                    if let last = lastBytes {
                        let dt = now.timeIntervalSince(last.1)
                        if dt > 0 { next.bitrateMbps = max(0, (bytes - last.0) * 8 / dt / 1_000_000) }
                    }
                    lastBytes = (bytes, now)
                }
                let received = (values["packetsReceived"] as? NSNumber)?.doubleValue ?? 0
                let lost = (values["packetsLost"] as? NSNumber)?.doubleValue ?? 0
                if let prev = lastPackets {
                    let dr = received - prev.received, dl = lost - prev.lost
                    if dr + dl > 0 { next.packetLossPercent = max(0, dl / (dr + dl) * 100) }
                }
                lastPackets = (received, lost)
                if let w = values["frameWidth"] as? NSNumber, let h = values["frameHeight"] as? NSNumber {
                    next.resolution = "\(w.intValue)x\(h.intValue)"
                }
            } else if stat.type == "candidate-pair",
                      (values["state"] as? String) == "succeeded",
                      (values["nominated"] as? NSNumber)?.boolValue ?? false,
                      let rtt = (values["currentRoundTripTime"] as? NSNumber)?.doubleValue {
                next.latencyMs = rtt * 1000
            }
        }
        stats = next
    }

    private func updateDemoStats() {
        var next = stats
        next.latencyMs = Double.random(in: 18...34)
        next.fps = Double.random(in: 58...60).rounded()
        next.bitrateMbps = Double.random(in: 11.5...14.5)
        next.packetLossPercent = Double.random(in: 0...0.3)
        next.resolution = "1920x1080"
        stats = next
    }

    // MARK: 演示模式（无需账号，用于预览界面）

    private func runDemo() async {
        let steps: [(ConnectStep, UInt64)] = [(.wake, 900), (.session, 1200), (.connect, 900), (.video, 600)]
        for (step, ms) in steps {
            enter(step)
            try? await Task.sleep(nanoseconds: ms * 1_000_000)
            if Task.isCancelled { return }
            finish(step)
        }
        if console.status == .offline {
            fail(.consoleOffline)
            return
        }
        hasFirstFrame = true
        streamStart = Date()
        withAnimation(Theme.Motion.spring) { phase = .streaming }
        Haptics.success()
        startStats()
    }

    func simulateDisconnect() {
        guard isDemo, phase == .streaming else { return }
        reconnectTask?.cancel()
        withAnimation(Theme.Motion.spring) { phase = .reconnecting(secondsLeft: 30) }
        reconnectTask = Task { [weak self] in
            for remaining in stride(from: 29, through: 27, by: -1) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.phase = .reconnecting(secondsLeft: remaining)
            }
            guard let self else { return }
            withAnimation(Theme.Motion.spring) { self.phase = .streaming }
        }
    }

    // MARK: 内部

    private func enter(_ step: ConnectStep) {
        stepStart = Date()
        withAnimation(Theme.Motion.spring) { phase = .connecting(step) }
    }

    private func finish(_ step: ConnectStep) {
        if stepDurations[step] == nil { stepDurations[step] = Date().timeIntervalSince(stepStart) }
        stepStart = Date()
    }

    private func fail(_ error: StreamError) {
        let step = currentStep
        teardown(stopSession: true, keepPhase: true)
        withAnimation(Theme.Motion.spring) { phase = .failed(error, at: step) }
        Haptics.error()
    }

    private func waitUntil(timeout: TimeInterval, _ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            if condition() { return }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    private func teardown(stopSession: Bool, keepPhase: Bool = false) {
        runTask?.cancel(); runTask = nil
        keepaliveTask?.cancel(); keepaliveTask = nil
        statsTask?.cancel(); statsTask = nil
        if !keepPhase { reconnectTask?.cancel(); reconnectTask = nil }
        channels?.stop(); channels = nil
        peer?.close(); peer = nil
        videoTrack = nil
        hasFirstFrame = false
        lastBytes = nil
        lastPackets = nil
        if stopSession, let client, let path = sessionPath {
            Task { await client.stop(sessionPath: path) }
        }
        sessionPath = nil
        InputHub.shared.reset()
    }
}

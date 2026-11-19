import Foundation
import SwiftUI
import WebRTC
import Network
#if os(macOS)
import AppKit
#else
import UIKit
#endif

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

/// 实际走的网络线路
enum StreamRoute: String, Equatable {
    case lan, publicIP, teredo, relay, unknown

    var label: LocalizedStringKey {
        switch self {
        case .lan: return "局域网直连"
        case .publicIP: return "经公网"
        case .teredo: return "经 Teredo 中继"
        case .relay: return "经中继服务器"
        case .unknown: return "线路未知"
        }
    }

    var isDirect: Bool { self == .lan }

    /// 根据远端候选的地址和类型判断线路
    static func classify(remoteAddress: String, candidateType: String?) -> StreamRoute {
        if candidateType == "relay" { return .relay }
        if remoteAddress.lowercased().hasPrefix("2001:") { return .teredo }
        if IcePreference.isPrivateIPv4(remoteAddress) { return .lan }
        if remoteAddress.isEmpty { return .unknown }
        return .publicIP
    }
}

struct StreamStats: Equatable {
    var latencyMs: Double?
    var fps: Double = 0
    var bitrateMbps: Double = 0
    var packetLossPercent: Double = 0
    var resolution: String?
    /// WebRTC 抖动缓冲平均等待（毫秒）
    var jitterMs: Double?
    /// 平均解码耗时（毫秒）
    var decodeMs: Double?
    /// 我们自己的画面节奏缓冲（毫秒，由画面模式决定）
    var pacingMs: Double = 0
    var route: StreamRoute = .unknown

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
    /// 云游戏时为对应的游戏；远程游玩自己的主机时为 nil
    let cloudTitle: CloudTitle?
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

    /// 实时字幕
    let captions = CaptionEngine()
    #if os(macOS)
    private var audioCapture: AppAudioCapture?
    #endif

    private let auth: XalAuthenticator?
    private let settings: AppSettings
    private var client: GssvClient?
    /// 当前串流令牌的过期时间，长时间游玩时提前换新
    private var tokenExpiresAt: Date?
    /// 睡眠唤醒 / 网络切换监听
    private var systemObservers: [NSObjectProtocol] = []
    private var pathMonitor: NWPathMonitor?
    private var lastInterfaces: [String]?
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
    private var lastJitter: (delay: Double, count: Double)?
    private var lastDecode: (time: Double, frames: Double)?
    private var lastBreakdownLog = Date.distantPast

    init(console: Console, auth: XalAuthenticator?, settings: AppSettings, isDemo: Bool) {
        self.console = console
        self.cloudTitle = nil
        self.auth = auth
        self.settings = settings
        self.isDemo = isDemo
    }

    /// 云游戏：用游戏信息构造一个虚拟「主机」，界面其余部分可以复用
    init(cloudTitle: CloudTitle, auth: XalAuthenticator?, settings: AppSettings, isDemo: Bool) {
        self.console = Console(id: "cloud-\(cloudTitle.id)", name: cloudTitle.name, kind: .unknown,
                               status: .online, consoleTypeRaw: "xCloud")
        self.cloudTitle = cloudTitle
        self.auth = auth
        self.settings = settings
        self.isDemo = isDemo
    }

    var isCloud: Bool { cloudTitle != nil }

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
        if duration > 5, !isCloud {
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
            let creds = try await (isCloud ? auth.cloudCredentials()
                                           : auth.streamingCredentials(offering: "xhome"))
            let client = GssvClient(baseURL: creds.baseURL, token: creds.gsToken, resolution: settings.resolution)
            self.client = client
            self.tokenExpiresAt = creds.expiresAt

            // 1. 唤醒主机 / 发起会话
            let start = try await client.startSession(kind: isCloud ? .cloud : .home,
                                                      target: cloudTitle?.id ?? console.id)
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
        // 云游戏可能需要排队，等待时间放宽
        let deadline = Date().addingTimeInterval(isCloud ? 600 : 90)
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
                guard !Task.isCancelled, let self else { return }
                // 令牌快过期时先换新，避免玩几个小时后掉线
                if TokenRenewal.shouldRenew(expiresAt: self.tokenExpiresAt, now: Date()) {
                    await self.renewStreamingToken(client: client)
                }
                var result = await client.keepalive(sessionPath: sessionPath)
                if result == .unauthorized {
                    // 令牌被拒：换新后再试一次
                    await self.renewStreamingToken(client: client)
                    result = await client.keepalive(sessionPath: sessionPath)
                }
                switch result {
                case .alive:
                    continue
                case .ended:
                    self.fail(.sessionFailed(String(localized: "会话已结束")))
                    return
                case .unauthorized:
                    self.fail(.notSignedIn)
                    return
                }
            }
        }
    }

    private func renewStreamingToken(client: GssvClient) async {
        guard let auth else { return }
        do {
            let creds = try await (isCloud ? auth.cloudCredentials(forceRefresh: true)
                                           : auth.streamingCredentials(offering: "xhome", forceRefresh: true))
            client.token = creds.gsToken
            tokenExpiresAt = creds.expiresAt
            debugLog("[Stream] 串流令牌已换新，有效期到 \(creds.expiresAt)")
        } catch {
            debugLog("[Stream] 串流令牌换新失败: \(error.localizedDescription)")
        }
    }

    // MARK: 字幕

    /// 打开 / 关闭字幕，或在切换识别语言后重启
    func updateCaptions(enabled: Bool, language: CaptionLanguage) {
        #if os(macOS)
        guard enabled, phase == .streaming || isReconnectingPhase else {
            stopCaptions()
            return
        }
        Task { @MainActor in
            await captions.start(language: language)
            guard case .running = captions.status else { return }
            if audioCapture == nil {
                let capture = AppAudioCapture()
                let feeder = captions.feeder
                capture.onBuffer = { feeder.append($0) }
                do {
                    try await capture.start()
                    audioCapture = capture
                } catch {
                    captions.stop()
                    captionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
        #endif
    }

    func stopCaptions() {
        #if os(macOS)
        audioCapture?.stop()
        audioCapture = nil
        #endif
        captions.stop()
    }

    /// 字幕启动失败的原因（显示给用户）
    @Published var captionError: String?

    private var isReconnectingPhase: Bool {
        if case .reconnecting = phase { return true }
        return false
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
        startSystemMonitoring()
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
    /// - Parameter rebuildAt: 倒计时到第几秒时重建会话（默认先给 ICE 15 秒自己恢复；睡眠唤醒后连接肯定已断，立刻重建）
    private func beginReconnect(rebuildAt: Int = 15) {
        reconnectTask?.cancel()
        withAnimation(Theme.Motion.spring) { phase = .reconnecting(secondsLeft: 30) }
        reconnectTask = Task { [weak self] in
            for remaining in stride(from: 29, through: 0, by: -1) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self else { return }
                guard case .reconnecting = self.phase else { return }
                self.phase = .reconnecting(secondsLeft: remaining)
                if remaining == rebuildAt {
                    // 中途尝试重建一次会话
                    self.teardown(stopSession: true, keepPhase: true)
                    self.hasFirstFrame = false
                    self.runTask = Task { [weak self] in await self?.run() }
                }
            }
            guard let self, case .reconnecting = self.phase else { return }
            self.fail(.iceFailed)
        }
    }

    // MARK: 睡眠唤醒 / 网络切换

    private func startSystemMonitoring() {
        guard !isDemo, systemObservers.isEmpty else { return }
        #if os(macOS)
        let center = NSWorkspace.shared.notificationCenter
        let wakeName = NSWorkspace.didWakeNotification
        #else
        let center = NotificationCenter.default
        let wakeName = UIApplication.willEnterForegroundNotification
        #endif
        systemObservers.append(center.addObserver(forName: wakeName, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleSystemWake() }
        })

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let interfaces = path.availableInterfaces.map(\.name)
            let satisfied = path.status == .satisfied
            Task { @MainActor in self?.handlePathChange(interfaces: interfaces, satisfied: satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "xr.path"))
        pathMonitor = monitor
    }

    private func stopSystemMonitoring() {
        #if os(macOS)
        let center = NSWorkspace.shared.notificationCenter
        #else
        let center = NotificationCenter.default
        #endif
        systemObservers.forEach { center.removeObserver($0) }
        systemObservers.removeAll()
        pathMonitor?.cancel()
        pathMonitor = nil
        lastInterfaces = nil
    }

    private func handleSystemWake() {
        guard phase == .streaming || isReconnectingPhase else { return }
        debugLog("[Stream] 设备从睡眠中唤醒，重新建立连接")
        beginReconnect(rebuildAt: 29)
    }

    private func handlePathChange(interfaces: [String], satisfied: Bool) {
        defer { lastInterfaces = interfaces }
        guard let previous = lastInterfaces, previous != interfaces, satisfied, phase == .streaming else { return }
        debugLog("[Stream] 网络切换 \(previous) → \(interfaces)，准备重连")
        beginReconnect()
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
                // 抖动缓冲：累计等待时间 / 输出帧数（取这一秒的增量）
                if let delay = (values["jitterBufferDelay"] as? NSNumber)?.doubleValue,
                   let count = (values["jitterBufferEmittedCount"] as? NSNumber)?.doubleValue {
                    if let prev = lastJitter, count - prev.count > 0 {
                        next.jitterMs = (delay - prev.delay) / (count - prev.count) * 1000
                    }
                    lastJitter = (delay, count)
                }
                // 解码耗时
                if let time = (values["totalDecodeTime"] as? NSNumber)?.doubleValue,
                   let frames = (values["framesDecoded"] as? NSNumber)?.doubleValue {
                    if let prev = lastDecode, frames - prev.frames > 0 {
                        next.decodeMs = (time - prev.time) / (frames - prev.frames) * 1000
                    }
                    lastDecode = (time, frames)
                }
            } else if stat.type == "candidate-pair",
                      (values["state"] as? String) == "succeeded",
                      (values["nominated"] as? NSNumber)?.boolValue ?? false {
                if let rtt = (values["currentRoundTripTime"] as? NSNumber)?.doubleValue {
                    next.latencyMs = rtt * 1000
                }
                if let remoteId = values["remoteCandidateId"] as? String,
                   let remote = report.statistics[remoteId]?.values {
                    let address = (remote["address"] as? String) ?? (remote["ip"] as? String) ?? ""
                    let route = StreamRoute.classify(remoteAddress: address, candidateType: remote["candidateType"] as? String)
                    if route != stats.route {
                        logPairs(report, selectedRemote: address, route: route)
                    }
                    next.route = route
                }
            }
        }
        #if os(macOS)
        next.pacingMs = settings.videoPacing == .lowLatency ? 0 : Double(settings.videoPacing.bufferMilliseconds)
        #endif
        if Date().timeIntervalSince(lastBreakdownLog) >= 5 {
            lastBreakdownLog = Date()
            func ms(_ v: Double?) -> String { v.map { String(format: "%.0f", $0) } ?? "—" }
            debugLog("[Stream] 延迟拆解: 网络往返 \(ms(next.latencyMs)) ms · 抖动缓冲 \(ms(next.jitterMs)) ms · 解码 \(ms(next.decodeMs)) ms · 画面模式 \(ms(next.pacingMs)) ms · 线路 \(next.route.rawValue) · \(String(format: "%.0f", next.fps)) fps")
        }
        stats = next
    }

    /// 线路变化时打印所有连通的候选对，便于排查
    private func logPairs(_ report: RTCStatisticsReport, selectedRemote: String, route: StreamRoute) {
        func describe(_ id: String?) -> String {
            guard let id, let v = report.statistics[id]?.values else { return "?" }
            let addr = (v["address"] as? String) ?? (v["ip"] as? String) ?? "?"
            let port = (v["port"] as? NSNumber)?.stringValue ?? "?"
            return "\(v["candidateType"] as? String ?? "?") \(v["protocol"] as? String ?? "?") \(addr):\(port)"
        }
        debugLog("[Stream] 实际线路: \(route.rawValue)（主机地址 \(selectedRemote)）")
        for (_, stat) in report.statistics where stat.type == "candidate-pair" {
            let v = stat.values
            guard (v["state"] as? String) == "succeeded" else { continue }
            let rtt = (v["currentRoundTripTime"] as? NSNumber).map { String(format: "%.0f ms", $0.doubleValue * 1000) } ?? "—"
            let nominated = (v["nominated"] as? NSNumber)?.boolValue ?? false
            debugLog("[Stream]   候选对 \(nominated ? "★" : " ") 本机 \(describe(v["localCandidateId"] as? String)) ⇄ 主机 \(describe(v["remoteCandidateId"] as? String)) RTT \(rtt)")
        }
    }

    private func updateDemoStats() {
        var next = stats
        next.latencyMs = Double.random(in: 18...34)
        next.fps = Double.random(in: 58...60).rounded()
        next.bitrateMbps = Double.random(in: 11.5...14.5)
        next.packetLossPercent = Double.random(in: 0...0.3)
        next.resolution = "1920x1080"
        next.jitterMs = Double.random(in: 8...14)
        next.decodeMs = Double.random(in: 2...4)
        next.route = .lan
        stats = next
    }

    // MARK: 演示模式（无需账号，用于预览界面）

    private func runDemo() async {
        let steps: [(ConnectStep, UInt64)] = [(.wake, 900), (.session, 1200), (.connect, 900), (.video, 600)]
        for (step, ms) in steps {
            enter(step)
            // 截图用：停在「建立连接」这一步
            if step == .connect && DebugLaunch.is("connecting") { return }
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
        // 断线重连时保持串流页 + 断线浮层，不切回连接页
        if case .reconnecting = phase { return }
        withAnimation(Theme.Motion.spring) { phase = .connecting(step) }
    }

    private func finish(_ step: ConnectStep) {
        if stepDurations[step] == nil { stepDurations[step] = Date().timeIntervalSince(stepStart) }
        stepStart = Date()
    }

    private func fail(_ error: StreamError) {
        let step = currentStep
        teardown(stopSession: true, keepPhase: true)
        stopCaptions()
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
        if !keepPhase { stopCaptions(); stopSystemMonitoring() }
        peer?.close(); peer = nil
        videoTrack = nil
        hasFirstFrame = false
        lastBytes = nil
        lastPackets = nil
        lastJitter = nil
        lastDecode = nil
        if stopSession, let client, let path = sessionPath {
            Task { await client.stop(sessionPath: path) }
        }
        sessionPath = nil
        InputHub.shared.reset()
    }
}

/// 何时换新串流令牌（纯函数，可单元测试）
enum TokenRenewal {
    /// 剩余不足这么多秒就换新
    static let margin: TimeInterval = 300

    static func shouldRenew(expiresAt: Date?, now: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) < margin
    }
}

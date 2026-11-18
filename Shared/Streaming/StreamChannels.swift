import Foundation
import QuartzCore

/// 服务器通过 message 通道弹出的系统对话框
struct ServerDialog: Identifiable, Equatable {
    var id: String          // transaction id
    var title: String
    var message: String
    var defaultButton: String
    var cancelButton: String?
}

/// 负责 message / control / input 三个数据通道的协议逻辑。
/// 流程对照参考实现 channel/message.ts、control.ts、input.ts：
/// message 通道打开 → 发送 Handshake → 收到 HandshakeAck → control 发授权 + 手柄已连接 → input 发客户端元数据并开始输入循环 → message 发设备配置。
final class StreamChannels {
    private let message: DataChannel?
    private let control: DataChannel?
    private let input: DataChannel?

    var onServerDisconnect: (() -> Void)?
    var onDialog: ((ServerDialog) -> Void)?
    var onVibration: ((VibrationReport) -> Void)?
    var onHandshake: (() -> Void)?

    /// 推流分辨率（通知主机的期望尺寸）
    var dimensions: (width: Int, height: Int) = (1920, 1080)

    private let queue = DispatchQueue(label: "xr.input", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var keyframeTimer: DispatchSourceTimer?
    private var sequence: UInt32 = 0
    private var pendingMetadata: [VideoMetadataFrame] = []
    private var lastSentState: GamepadState?
    private var lastSentTime: CFTimeInterval = 0
    private let metadataLock = NSLock()
    private var started = false
    private let startTime = CACurrentMediaTime()

    init(peer: StreamPeer) {
        message = peer.channel("message")
        control = peer.channel("control")
        input = peer.channel("input")

        message?.onOpen = { [weak self] in self?.sendHandshake() }
        message?.onMessage = { [weak self] data in self?.handleMessage(data) }
        input?.onMessage = { [weak self] data in self?.handleInput(data) }

        peer.frameTap.onMetadata = { [weak self] frame in
            guard let self else { return }
            self.metadataLock.lock()
            self.pendingMetadata.append(frame)
            if self.pendingMetadata.count > 30 { self.pendingMetadata.removeFirst(self.pendingMetadata.count - 30) }
            self.metadataLock.unlock()
        }
    }

    func stop() {
        timer?.cancel(); timer = nil
        keyframeTimer?.cancel(); keyframeTimer = nil
    }

    func requestKeyframe() {
        sendJSON(control, ["message": "videoKeyframeRequested", "ifrRequested": true])
    }

    // MARK: message 通道

    private func sendHandshake() {
        sendJSON(message, [
            "type": "Handshake",
            "version": "messageV1",
            "id": UUID().uuidString.lowercased(),
            "cv": "0"
        ])
    }

    private func handleMessage(_ data: Data) {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = obj["type"] as? String else { return }
        switch type {
        case "HandshakeAck":
            guard !started else { return }
            started = true
            sendAuthorization()
            startInput()
            sendConfig()
            DispatchQueue.main.async { [weak self] in self?.onHandshake?() }
        case "TransactionStart", "Message":
            handleTransaction(obj)
        default:
            break
        }
    }

    private func handleTransaction(_ obj: [String: Any]) {
        let target = obj["target"] as? String ?? ""
        let id = obj["id"] as? String ?? ""
        switch target {
        case "/streaming/sessionLifetimeManagement/serverInitiatedDisconnect":
            completeTransaction(id: id, content: "")
            DispatchQueue.main.async { [weak self] in self?.onServerDisconnect?() }
        case "/streaming/systemUi/messages/ShowMessageDialog":
            let content = (obj["content"] as? String).flatMap { $0.data(using: .utf8) }
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            let dialog = ServerDialog(
                id: id,
                title: content["TitleText"] as? String ?? "",
                message: content["ContentText"] as? String ?? "",
                defaultButton: content["CommandLabel1"] as? String ?? String(localized: "确定"),
                cancelButton: content["CommandLabel2"] as? String
            )
            DispatchQueue.main.async { [weak self] in self?.onDialog?(dialog) }
        default:
            break
        }
    }

    /// 回应服务器对话框：result 0 = 确认，1 = 取消
    func answerDialog(id: String, result: Int) {
        completeTransaction(id: id, contentObject: ["Result": result])
    }

    private func completeTransaction(id: String, content: String) {
        let encoded = (try? JSONSerialization.data(withJSONObject: [content], options: .fragmentsAllowed))
            .flatMap { String(data: $0, encoding: .utf8) }
        // JSON.stringify("") == "\"\""
        let contentString = encoded.map { String($0.dropFirst().dropLast()) } ?? "\"\""
        sendJSON(message, ["type": "TransactionComplete", "content": contentString, "id": id, "cv": ""])
    }

    private func completeTransaction(id: String, contentObject: [String: Any]) {
        let content = (try? JSONSerialization.data(withJSONObject: contentObject)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        sendJSON(message, ["type": "TransactionComplete", "content": content, "id": id, "cv": ""])
    }

    private func sendConfig() {
        func messageFor(_ target: String, _ content: [String: Any]) -> [String: Any] {
            let contentString = (try? JSONSerialization.data(withJSONObject: content)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            return ["type": "Message", "content": contentString, "id": UUID().uuidString.lowercased(), "target": target, "cv": ""]
        }
        let (w, h) = dimensions
        sendJSON(message, messageFor("/streaming/systemUi/configuration", ["version": [0, 2, 0], "systemUis": [Int]()]))
        sendJSON(message, messageFor("/streaming/properties/clientappinstallidchanged", ["clientAppInstallId": InstallID.value]))
        sendJSON(message, messageFor("/streaming/characteristics/orientationchanged", ["orientation": 0]))
        sendJSON(message, messageFor("/streaming/characteristics/touchinputenabledchanged", ["touchInputEnabled": false]))
        sendJSON(message, messageFor("/streaming/characteristics/clientdevicecapabilities", [:]))
        sendJSON(message, messageFor("/streaming/characteristics/dimensionschanged", [
            "horizontal": w, "vertical": h,
            "preferredWidth": w, "preferredHeight": h,
            "safeAreaLeft": 0, "safeAreaTop": 0,
            "safeAreaRight": w, "safeAreaBottom": h,
            "supportsCustomResolution": true
        ]))
    }

    // MARK: control 通道

    private func sendAuthorization() {
        sendJSON(control, ["message": "authorizationRequest", "accessKey": "4BDB3609-C1F1-4195-9B37-FEFF45DA8B8E"])
        sendJSON(control, ["message": "gamepadChanged", "gamepadIndex": 0, "wasAdded": true])

        // 定期请求关键帧，减少花屏后的恢复时间
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 5, repeating: 5)
        t.setEventHandler { [weak self] in self?.requestKeyframe() }
        t.resume()
        keyframeTimer = t
    }

    // MARK: input 通道

    private func startInput() {
        input?.send(data: InputPacketEncoder.clientMetadata(sequence: 0, timestampMs: nowMs(), maxTouchpoints: 1))
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .milliseconds(16), repeating: .milliseconds(8), leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    /// 每 8ms 检查一次：有新视频帧元数据或手柄状态变化就发送；空闲时每 100ms 发一次保持状态。
    private func tick() {
        guard let input, input.isOpen else { return }
        metadataLock.lock()
        let metadata = pendingMetadata
        pendingMetadata.removeAll()
        metadataLock.unlock()

        let state = InputHub.shared.current()
        let now = CACurrentMediaTime()
        let changed = state != lastSentState
        let heartbeat = now - lastSentTime > 0.1
        guard !metadata.isEmpty || changed || heartbeat else { return }

        sequence &+= 1
        let packet = InputPacketEncoder.inputReport(
            sequence: sequence,
            timestampMs: nowMs(),
            metadata: metadata,
            gamepads: (changed || heartbeat || !metadata.isEmpty) ? [GamepadFrame(index: 0, state: state)] : []
        )
        input.send(data: packet)
        lastSentState = state
        lastSentTime = now
    }

    private func handleInput(_ data: Data) {
        if let vibration = VibrationReport.parse(data) {
            DispatchQueue.main.async { [weak self] in self?.onVibration?(vibration) }
        }
    }

    // MARK: 工具

    private func nowMs() -> Double { (CACurrentMediaTime() - startTime) * 1000 }

    private func sendJSON(_ channel: DataChannel?, _ object: [String: Any]) {
        guard let channel,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        channel.send(text: text)
    }
}

/// 每次安装固定的客户端 ID
enum InstallID {
    static let value: String = {
        let key = "xr.clientAppInstallId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()
}

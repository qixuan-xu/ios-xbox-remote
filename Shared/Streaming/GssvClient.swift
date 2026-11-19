import Foundation

enum StreamError: LocalizedError, Equatable {
    case remoteDisabled
    case consoleOffline
    case sessionFailed(String)
    case iceFailed
    case timeout
    case noVideo
    case http(Int, String)
    case notSignedIn
    case other(String)

    var errorDescription: String? {
        switch self {
        case .remoteDisabled: return String(localized: "主机未开启远程功能")
        case .consoleOffline: return String(localized: "主机处于离线状态，请把电源模式设为「睡眠」")
        case .sessionFailed(let msg): return msg.isEmpty ? String(localized: "主机拒绝了串流请求") : msg
        case .iceFailed: return String(localized: "当前网络无法建立直连，请切换网络后重试")
        case .timeout: return String(localized: "连接超时，请确认主机已开机或处于睡眠模式")
        case .noVideo: return String(localized: "已连接，但没有收到画面")
        case .http(let code, _): return String(localized: "串流服务返回错误（\(code)）")
        case .notSignedIn: return String(localized: "登录已过期，请重新登录")
        case .other(let msg): return msg
        }
    }

    var helpHint: String? {
        switch self {
        case .remoteDisabled:
            return String(localized: "在主机上打开 设置 > 设备与连接 > 远程功能，勾选「启用远程功能」。")
        case .consoleOffline:
            return String(localized: "在主机上打开 设置 > 常规 > 电源选项，把电源模式改为「睡眠」。")
        case .iceFailed:
            return String(localized: "尝试切换到 Wi-Fi 或 5G，或在路由器上开启 UPnP。")
        default:
            return nil
        }
    }
}

/// 串流 REST 接口（xhome / xcloud 的 gssv 服务）。字段对照 xbox-xcloud-player 的 apiclient.ts / lib/stream.ts。
final class GssvClient {
    enum Kind: String { case home, cloud }

    struct ConsoleDTO: Decodable {
        var deviceName: String
        var serverId: String
        var powerState: String
        var consoleType: String
        var playPath: String?
        var outOfHomeWarning: Bool?
        var wirelessWarning: Bool?
        var isDevKit: Bool?
    }
    struct ConsolesResponse: Decodable {
        var totalItems: Int?
        var results: [ConsoleDTO]
    }
    struct StartResponse: Decodable {
        var sessionId: String?
        var sessionPath: String
        var state: String?
    }
    struct ErrorDetails: Decodable {
        var code: String?
        var message: String?
    }
    struct StateResponse: Decodable {
        var state: String
        var errorDetails: ErrorDetails?
    }
    struct ExchangeResponse: Decodable {
        var exchangeResponse: String?
        var errorDetails: ErrorDetails?
    }
    struct IceCandidateDTO: Codable, Equatable {
        var candidate: String
        var sdpMid: String?
        var sdpMLineIndex: Int32?
        var usernameFragment: String?
    }

    let baseURL: URL
    /// 串流令牌；长时间游玩时会在中途换新，所以加锁保存
    var token: String {
        get { tokenLock.lock(); defer { tokenLock.unlock() }; return _token }
        set { tokenLock.lock(); _token = newValue; tokenLock.unlock() }
    }
    private var _token: String
    private let tokenLock = NSLock()
    let resolution: StreamResolution
    let locale: String
    private let session: URLSession

    init(baseURL: URL, token: String, resolution: StreamResolution, session: URLSession = .shared) {
        self.baseURL = baseURL
        self._token = token
        self.resolution = resolution
        self.session = session
        let lang = Locale.preferredLanguages.first ?? "en-US"
        self.locale = lang.contains("zh") ? "zh-CN" : lang
    }

    // MARK: 接口

    func consoles() async throws -> [Console] {
        let (data, _) = try await request("GET", "/v6/servers/home")
        let response = try JSONDecoder().decode(ConsolesResponse.self, from: data)
        return response.results.map {
            Console(id: $0.serverId,
                    name: $0.deviceName,
                    kind: ConsoleKind(consoleType: $0.consoleType),
                    status: ConsoleStatus(powerState: $0.powerState),
                    consoleTypeRaw: $0.consoleType,
                    outOfHomeWarning: $0.outOfHomeWarning ?? false,
                    wirelessWarning: $0.wirelessWarning ?? false,
                    isDevKit: $0.isDevKit ?? false)
        }
    }

    func startSession(kind: Kind, target: String) async throws -> StartResponse {
        let body: [String: Any] = [
            "clientSessionId": "",
            "titleId": kind == .cloud ? target : "",
            "systemUpdateGroup": "",
            "settings": [
                "nanoVersion": "V3;WebrtcTransport.dll",
                "enableOptionalDataCollection": false,
                "enableTextToSpeech": false,
                "highContrast": 0,
                "locale": locale,
                "useIceConnection": false,
                "timezoneOffsetMinutes": TimeZone.current.secondsFromGMT() / 60,
                "sdkType": "web",
                "osName": osName
            ],
            "serverId": kind == .home ? target : "",
            "fallbackRegionNames": [String]()
        ]
        let (data, _) = try await request("POST", "/v5/sessions/\(kind.rawValue)/play", json: body)
        return try JSONDecoder().decode(StartResponse.self, from: data)
    }

    func state(sessionPath: String) async throws -> StateResponse {
        let (data, _) = try await request("GET", path(sessionPath, "state"))
        return try JSONDecoder().decode(StateResponse.self, from: data)
    }

    func sendSDPOffer(sessionPath: String, sdp: String) async throws {
        let body: [String: Any] = [
            "messageType": "offer",
            "sdp": sdp,
            "requestId": "1",
            "configuration": [
                "chatConfiguration": [
                    "bytesPerSample": 2,
                    "expectedClipDurationMs": 20,
                    "format": ["codec": "opus", "container": "webm"],
                    "numChannels": 1,
                    "sampleFrequencyHz": 24000
                ],
                "chat": ["minVersion": 1, "maxVersion": 1],
                "control": ["minVersion": 1, "maxVersion": 3],
                // 与 Greenlight 使用的已发布版本一致（输入协议 v8）
                "input": ["minVersion": 1, "maxVersion": 8],
                "message": ["minVersion": 1, "maxVersion": 1]
            ]
        ]
        _ = try await request("POST", path(sessionPath, "sdp"), json: body, allowEmpty: true)
    }

    /// 轮询 SDP 应答，返回远端 SDP
    func waitForSDPAnswer(sessionPath: String, timeout: TimeInterval = 30) async throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            let (data, http) = try await request("GET", path(sessionPath, "sdp"), allowEmpty: true)
            if http.statusCode != 204, !data.isEmpty {
                let ex = try JSONDecoder().decode(ExchangeResponse.self, from: data)
                if let raw = ex.exchangeResponse, let inner = raw.data(using: .utf8),
                   let obj = try JSONSerialization.jsonObject(with: inner) as? [String: Any] {
                    if let status = obj["status"] as? String, status.lowercased() != "success",
                       obj["sdp"] == nil {
                        throw StreamError.sessionFailed(String(localized: "主机拒绝了连接参数（\(status)）"))
                    }
                    if let sdp = obj["sdp"] as? String { return sdp }
                }
                if let err = ex.errorDetails { throw StreamError.sessionFailed(err.message ?? err.code ?? "") }
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw StreamError.timeout
    }

    func sendICECandidates(sessionPath: String, candidates: [IceCandidateDTO]) async throws {
        // 格式与 Greenlight 一致：{ messageType: "iceCandidate", candidate: [{ candidate, sdpMLineIndex, sdpMid }] }
        let list: [[String: Any]] = candidates.map {
            ["candidate": $0.candidate, "sdpMLineIndex": Int($0.sdpMLineIndex ?? 0), "sdpMid": $0.sdpMid ?? "0"]
        }
        _ = try await request("POST", path(sessionPath, "ice"), json: ["messageType": "iceCandidate", "candidate": list], allowEmpty: true)
    }

    func waitForRemoteICE(sessionPath: String, timeout: TimeInterval = 30) async throws -> [IceCandidateDTO] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            let (data, http) = try await request("GET", path(sessionPath, "ice"), allowEmpty: true)
            if http.statusCode != 204, !data.isEmpty {
                let ex = try JSONDecoder().decode(ExchangeResponse.self, from: data)
                if let raw = ex.exchangeResponse {
                    debugLog("[Stream] 远端 ICE: \(raw.prefix(1500))")
                    let list = Self.parseCandidates(raw)
                    debugLog("[Stream] 解析出 \(list.count) 个远端候选")
                    return list
                }
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw StreamError.timeout
    }

    /// 宽松解析远端候选：sdpMLineIndex 可能是数字也可能是字符串，字段缺失时给默认值
    static func parseCandidates(_ raw: String) -> [IceCandidateDTO] {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let items: [Any]
        if let array = obj as? [Any] { items = array }
        else if let dict = obj as? [String: Any], let array = (dict["candidates"] ?? dict["candidate"]) as? [Any] { items = array }
        else { return [] }
        return items.compactMap { item -> IceCandidateDTO? in
            var dict = item as? [String: Any]
            if dict == nil, let s = item as? String, let d = s.data(using: .utf8) {
                dict = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
            }
            guard let dict, let candidate = dict["candidate"] as? String else { return nil }
            var index: Int32 = 0
            if let n = dict["sdpMLineIndex"] as? NSNumber { index = n.int32Value }
            else if let s = dict["sdpMLineIndex"] as? String, let n = Int32(s) { index = n }
            let mid = (dict["sdpMid"] as? String) ?? (dict["sdpMid"] as? NSNumber)?.stringValue
            return IceCandidateDTO(candidate: candidate, sdpMid: mid, sdpMLineIndex: index)
        }
    }

    enum KeepaliveResult { case alive, ended, unauthorized }

    func keepalive(sessionPath: String) async -> KeepaliveResult {
        let result: (Data, HTTPURLResponse)
        do {
            result = try await request("POST", path(sessionPath, "keepalive"), body: Data(), allowEmpty: true)
        } catch StreamError.notSignedIn {
            return .unauthorized
        } catch {
            // 网络抖动等临时错误：下次再试，不判定会话结束
            return .alive
        }
        if let obj = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any],
           let code = obj["code"] as? String,
           code == "SessionNotActive" || code == "SessionNotFound" {
            return .ended
        }
        return .alive
    }

    func connect(sessionPath: String, userToken: String) async throws {
        _ = try await request("POST", path(sessionPath, "connect"), json: ["userToken": userToken], allowEmpty: true)
    }

    func stop(sessionPath: String) async {
        _ = try? await request("DELETE", "/" + sessionPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")), allowEmpty: true)
    }

    /// 给其他文件里的扩展使用的通用 GET
    func requestData(_ method: String, _ path: String) async throws -> (Data, HTTPURLResponse) {
        try await request(method, path)
    }

    // MARK: 内部

    private var osName: String { resolution == .p720 ? "android" : "windows" }

    private func path(_ sessionPath: String, _ suffix: String) -> String {
        "/" + sessionPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + suffix
    }

    var deviceInfo: String {
        let dims = resolution.dimensions
        let info: [String: Any] = [
            "appInfo": [
                "env": [
                    "clientAppId": "www.xbox.com",
                    "clientAppType": "browser",
                    "clientAppVersion": "21.1.98",
                    "clientSdkVersion": "8.5.3",
                    "httpEnvironment": "prod",
                    "sdkInstallId": ""
                ]
            ],
            "dev": [
                "hw": ["make": "Microsoft", "model": "unknown", "sdktype": "web"],
                "os": ["name": osName, "ver": "22631.2715", "platform": "desktop"],
                "displayInfo": [
                    "dimensions": ["widthInPixels": dims.width, "heightInPixels": dims.height],
                    "pixelDensity": ["dpiX": 2, "dpiY": 2]
                ],
                "browser": ["browserName": "chrome", "browserVersion": "119.0"]
            ]
        ]
        let data = (try? JSONSerialization.data(withJSONObject: info)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    @discardableResult
    private func request(_ method: String,
                         _ path: String,
                         json: [String: Any]? = nil,
                         body: Data? = nil,
                         allowEmpty: Bool = false) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw StreamError.other("bad url \(path)") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("XboxComBrowser", forHTTPHeaderField: "X-Gssv-Client")
        req.setValue(deviceInfo, forHTTPHeaderField: "X-MS-Device-Info")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let json { req.httpBody = try JSONSerialization.data(withJSONObject: json) }
        else if let body { req.httpBody = body }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw StreamError.other("no http response") }
        debugLog("[Stream] \(method) \(url.path) → \(http.statusCode) (\(data.count) bytes)")
        if !(200..<300).contains(http.statusCode) {
            debugLog("[Stream] 返回内容: \(String(data: data, encoding: .utf8)?.prefix(1000) ?? "")")
        }
        if http.statusCode == 401 || http.statusCode == 403 { throw StreamError.notSignedIn }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            if text.contains("RemoteDisabled") || text.contains("RemoteManagementDisabled") { throw StreamError.remoteDisabled }
            if text.contains("ConsoleOffline") || text.contains("NotAvailable") { throw StreamError.consoleOffline }
            throw StreamError.http(http.statusCode, text)
        }
        // 只有需要解析内容的 GET 才要求有返回体；POST / DELETE（sdp、ice、keepalive 等）服务器常返回空内容
        if data.isEmpty && !allowEmpty && method == "GET" && http.statusCode != 204 {
            throw StreamError.other(String(localized: "服务器返回空内容：\(url.path)"))
        }
        return (data, http)
    }
}

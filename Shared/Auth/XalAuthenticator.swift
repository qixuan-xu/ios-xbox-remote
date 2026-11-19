import Foundation
import CryptoKit

/// 认证错误，带用户能看懂的说明
enum XboxAuthError: LocalizedError {
    case http(status: Int, url: String, body: String, xerr: String?)
    case invalidResponse(String)
    case stateMismatch
    case cancelled
    case notSignedIn
    case noXboxAccount
    case childAccount
    case regionUnsupported
    case accountSetupRequired(String)

    var errorDescription: String? {
        switch self {
        case .http(let status, _, _, _):
            return String(localized: "登录服务返回错误（\(status)），请稍后重试")
        case .invalidResponse(let detail):
            return String(localized: "登录服务返回了无法识别的数据") + "（\(detail)）"
        case .stateMismatch:
            return String(localized: "登录验证失败，请重新登录")
        case .cancelled:
            return String(localized: "已取消登录")
        case .notSignedIn:
            return String(localized: "请先登录 Microsoft 账号")
        case .noXboxAccount:
            return String(localized: "这个 Microsoft 账号还没有 Xbox 档案，请先在 Xbox 上创建")
        case .childAccount:
            return String(localized: "儿童账号需要家长在 Xbox 家庭设置里允许")
        case .regionUnsupported:
            return String(localized: "当前地区不支持 Xbox 串流服务")
        case .accountSetupRequired:
            return String(localized: "这个账号需要先在 Xbox 网站上完成设置（例如创建 Xbox 档案）")
        }
    }
}

// MARK: - 服务器响应模型

struct XboxToken: Codable {
    var IssueInstant: String?
    var NotAfter: String?
    var Token: String
    var DisplayClaims: DisplayClaimsBox?

    var expiry: Date? { NotAfter.flatMap(XboxDate.parse) }
}

/// DisplayClaims 里的 xui / xti 结构不固定，宽松解析
struct DisplayClaimsBox: Codable {
    var xui: [[String: String]]?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        xui = try? c.decodeIfPresent([[String: String]].self, forKey: .xui)
    }

    enum CodingKeys: String, CodingKey { case xui }
}

/// SISU 授权的原始返回：字段全部可选，缺什么在上层判断
struct SisuAuthorizeRaw: Decodable {
    var DeviceToken: String?
    var TitleToken: XboxToken?
    var UserToken: XboxToken?
    var AuthorizationToken: XboxToken?
    var WebPage: String?
}

struct SisuAuthorizeResponse: Codable {
    var DeviceToken: String
    var TitleToken: XboxToken
    var UserToken: XboxToken
    var AuthorizationToken: XboxToken

    var userHash: String? { AuthorizationToken.DisplayClaims?.xui?.first?["uhs"] }
    var gamertag: String? {
        let claims = AuthorizationToken.DisplayClaims?.xui?.first
        return claims?["mgt"] ?? claims?["gtg"]
    }
    var xuid: String? { AuthorizationToken.DisplayClaims?.xui?.first?["xid"] }
}

struct MsaTokenResponse: Codable {
    var token_type: String?
    var expires_in: Int?
    var scope: String?
    var access_token: String
    var refresh_token: String?
    var user_id: String?
}

struct StreamingTokenResponse: Codable {
    struct Region: Codable {
        var name: String
        var baseUri: String
        var isDefault: Bool
        var networkTestHostname: String?
        var fallbackPriority: Int?
    }
    struct OfferingSettings: Codable {
        var regions: [Region]
    }
    var offeringSettings: OfferingSettings
    var market: String?
    var gsToken: String
    var tokenType: String?
    var durationInSeconds: Int

    var defaultRegion: Region? { offeringSettings.regions.first(where: \.isDefault) ?? offeringSettings.regions.first }
}

/// 已取得的串流令牌（带过期时间）
struct StreamingCredentials {
    var offering: String
    var gsToken: String
    var baseURL: URL
    var regionName: String
    var expiresAt: Date
    var isValid: Bool { expiresAt.timeIntervalSinceNow > 60 }
}

enum XboxDate {
    /// NotAfter 形如 2024-05-01T12:34:56.1234567Z，小数位数不固定
    static func parse(_ string: String) -> Date? {
        var s = string
        if let dot = s.firstIndex(of: ".") {
            let afterDot = s.index(after: dot)
            let fractionEnd = s[afterDot...].firstIndex(where: { !$0.isNumber }) ?? s.endIndex
            let suffix = fractionEnd < s.endIndex ? String(s[fractionEnd...]) : "Z"
            s = String(s[..<dot]) + suffix
        }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

// MARK: - 认证流程

/// 登录进行中需要保留的上下文
struct PendingSignIn {
    var authorizeURL: URL
    var state: String
    var codeChallenge: CodeChallenge
    var sessionId: String?
}

/// Xbox 认证：设备令牌 → SISU 登录 → 换取用户令牌 → SISU 授权 → XSTS → 串流令牌。
/// 流程与字段对照开源实现 xal-node。
actor XalAuthenticator {
    static let appId = "000000004c20a908"
    static let titleId = "328178078"
    static let redirectScheme = "ms-xal-000000004c20a908"
    static let redirectUri = "ms-xal-000000004c20a908://auth"
    static let msaScope = "service::user.auth.xboxlive.com::MBI_SSL"
    static let transferTokenScope = "service::http://Passport.NET/purpose::PURPOSE_XBOX_CLOUD_CONSOLE_TRANSFER_TOKEN"

    private var credentials: StoredCredentials
    private var signer: RequestSigner
    private let session: URLSession

    private var deviceToken: XboxToken?
    private var sisu: SisuAuthorizeResponse?
    private var streaming: [String: StreamingCredentials] = [:]
    private var webToken: XboxToken?

    init(session: URLSession = .shared) {
        self.session = session
        if let stored = TokenStore.load(),
           let key = try? P256.Signing.PrivateKey(rawRepresentation: stored.privateKey) {
            credentials = stored
            signer = RequestSigner(privateKey: key)
        } else {
            let key = P256.Signing.PrivateKey()
            credentials = StoredCredentials(
                privateKey: key.rawRepresentation,
                deviceId: "{\(UUID().uuidString)}",
                serialNumber: "{\(UUID().uuidString)}",
                refreshToken: nil,
                userId: nil,
                profile: nil
            )
            signer = RequestSigner(privateKey: key)
        }
    }

    var hasStoredLogin: Bool { credentials.refreshToken != nil }
    var storedProfile: UserProfile? { credentials.profile }

    // MARK: 登录

    /// 第一步：拿到微软登录页地址
    func beginSignIn() async throws -> PendingSignIn {
        let device = try await fetchDeviceToken()
        let challenge = CodeChallenge.generate()
        let state = Data.random(count: 32).base64URLEncodedString()

        let payload: [String: Any] = [
            "AppId": Self.appId,
            "TitleId": Self.titleId,
            "RedirectUri": Self.redirectUri,
            "DeviceToken": device.Token,
            "Sandbox": "RETAIL",
            "TokenType": "code",
            "Offers": [Self.msaScope],
            "Query": [
                "display": "android_phone",
                "code_challenge": challenge.challenge,
                "code_challenge_method": challenge.method,
                "state": state
            ]
        ]
        let (data, response) = try await signedPost("https://sisu.xboxlive.com/authenticate", json: payload)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let redirect = obj?["MsaOauthRedirect"] as? String, let url = URL(string: redirect) else {
            AuthLog.log("SISU 登录返回: \(String(data: data, encoding: .utf8) ?? "")")
            throw XboxAuthError.invalidResponse("SISU 登录没有返回登录地址")
        }
        let sessionId = response.value(forHTTPHeaderField: "X-SessionId")
        return PendingSignIn(authorizeURL: url, state: state, codeChallenge: challenge, sessionId: sessionId)
    }

    /// 第二步：网页登录完成后，用回调地址里的 code 换取令牌
    func completeSignIn(_ pending: PendingSignIn, callbackURL: URL) async throws -> UserProfile {
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }
        if value("error") != nil { throw XboxAuthError.cancelled }
        AuthLog.log("callback: \(callbackURL.absoluteString.prefix(200))")
        guard let code = value("code") else { throw XboxAuthError.invalidResponse("回调里没有 code") }
        guard value("state") == pending.state else { throw XboxAuthError.stateMismatch }

        let msa = try await tokenRequest([
            "client_id": Self.appId,
            "code": code,
            "code_verifier": pending.codeChallenge.verifier,
            "grant_type": "authorization_code",
            "redirect_uri": Self.redirectUri,
            "scope": Self.msaScope
        ])
        credentials.refreshToken = msa.refresh_token
        credentials.userId = msa.user_id
        let device = try await fetchDeviceToken()
        let sisu = try await sisuAuthorize(accessToken: msa.access_token, deviceToken: device.Token, sessionId: pending.sessionId)
        self.sisu = sisu
        let profile = await buildProfile(from: sisu)
        credentials.profile = profile
        TokenStore.save(credentials)
        return profile
    }

    /// 启动时静默刷新
    func refresh() async throws -> UserProfile {
        guard let refreshToken = credentials.refreshToken else { throw XboxAuthError.notSignedIn }
        let msa = try await tokenRequest([
            "client_id": Self.appId,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": Self.msaScope
        ])
        if let newRefresh = msa.refresh_token { credentials.refreshToken = newRefresh }
        let device = try await fetchDeviceToken()
        let sisu = try await sisuAuthorize(accessToken: msa.access_token, deviceToken: device.Token, sessionId: nil)
        self.sisu = sisu
        streaming.removeAll()
        webToken = nil
        let profile = await buildProfile(from: sisu)
        credentials.profile = profile
        TokenStore.save(credentials)
        return profile
    }

    func signOut() {
        TokenStore.clear()
        let key = P256.Signing.PrivateKey()
        credentials = StoredCredentials(privateKey: key.rawRepresentation,
                                        deviceId: "{\(UUID().uuidString)}",
                                        serialNumber: "{\(UUID().uuidString)}")
        signer = RequestSigner(privateKey: key)
        sisu = nil
        deviceToken = nil
        streaming.removeAll()
        webToken = nil
    }

    // MARK: 串流令牌

    /// offering："xhome"（远程游玩自己的主机）或 "xgpuweb"（云游戏）
    func streamingCredentials(offering: String = "xhome", forceRefresh: Bool = false) async throws -> StreamingCredentials {
        if forceRefresh { streaming[offering] = nil }
        if let cached = streaming[offering], cached.isValid { return cached }
        let sisu = try await currentSisu()
        let xsts = try await xstsAuthorize(sisu: sisu, relyingParty: "http://gssv.xboxlive.com/")

        let url = URL(string: "https://\(offering).gssv-play-prod.xboxlive.com/v2/login/user")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store, must-revalidate, no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("XboxComBrowser", forHTTPHeaderField: "x-gssv-client")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["token": xsts.Token, "offeringId": offering])
        let (data, _) = try await send(request)
        let token = try decode(StreamingTokenResponse.self, data, step: "串流令牌")
        guard let region = token.defaultRegion, let base = URL(string: region.baseUri) else {
            throw XboxAuthError.regionUnsupported
        }
        let creds = StreamingCredentials(
            offering: offering,
            gsToken: token.gsToken,
            baseURL: base,
            regionName: region.name,
            expiresAt: Date().addingTimeInterval(TimeInterval(token.durationInSeconds))
        )
        streaming[offering] = creds
        return creds
    }

    /// 云游戏令牌：先试 Game Pass Ultimate（xgpuweb），失败再试免费游戏（xgpuwebf2p）
    func cloudCredentials(forceRefresh: Bool = false) async throws -> StreamingCredentials {
        do {
            return try await streamingCredentials(offering: "xgpuweb", forceRefresh: forceRefresh)
        } catch {
            do {
                return try await streamingCredentials(offering: "xgpuwebf2p", forceRefresh: forceRefresh)
            } catch {
                throw XboxAuthError.regionUnsupported
            }
        }
    }

    /// 云游戏 ReadyToConnect 时需要提交的转移令牌
    func transferToken() async throws -> String {
        guard let refreshToken = credentials.refreshToken else { throw XboxAuthError.notSignedIn }
        let msa = try await tokenRequest([
            "client_id": Self.appId,
            "grant_type": "refresh_token",
            "scope": Self.transferTokenScope,
            "refresh_token": refreshToken
        ])
        return msa.access_token
    }

    // MARK: 内部步骤

    private func currentSisu() async throws -> SisuAuthorizeResponse {
        if let sisu, let expiry = sisu.AuthorizationToken.expiry, expiry.timeIntervalSinceNow > 120 {
            return sisu
        }
        _ = try await refresh()
        guard let sisu else { throw XboxAuthError.notSignedIn }
        return sisu
    }

    private func fetchDeviceToken() async throws -> XboxToken {
        if let deviceToken, let expiry = deviceToken.expiry, expiry.timeIntervalSinceNow > 300 {
            return deviceToken
        }
        let payload: [String: Any] = [
            "Properties": [
                "AuthMethod": "ProofOfPossession",
                "Id": credentials.deviceId,
                "DeviceType": "Android",
                "SerialNumber": credentials.serialNumber,
                "Version": "15.0",
                "ProofKey": signer.proofKey
            ],
            "RelyingParty": "http://auth.xboxlive.com",
            "TokenType": "JWT"
        ]
        let (data, _) = try await signedPost("https://device.auth.xboxlive.com/device/authenticate", json: payload)
        let token = try decode(XboxToken.self, data, step: "设备令牌")
        deviceToken = token
        return token
    }

    private func sisuAuthorize(accessToken: String, deviceToken: String, sessionId: String?) async throws -> SisuAuthorizeResponse {
        var payload: [String: Any] = [
            "AccessToken": "t=\(accessToken)",
            "AppId": Self.appId,
            "DeviceToken": deviceToken,
            "Sandbox": "RETAIL",
            "SiteName": "user.auth.xboxlive.com",
            "UseModernGamertag": true,
            "ProofKey": signer.proofKey
        ]
        if let sessionId { payload["SessionId"] = sessionId }
        let (data, _) = try await signedPost("https://sisu.xboxlive.com/authorize", json: payload)
        let raw = try decode(SisuAuthorizeRaw.self, data, step: "SISU 授权")
        guard let title = raw.TitleToken, let user = raw.UserToken, let auth = raw.AuthorizationToken else {
            let keys = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?.keys.sorted().joined(separator: ",") ?? "?"
            AuthLog.log("SISU 授权返回: \(String(data: data, encoding: .utf8)?.prefix(2000) ?? "")")
            if let page = raw.WebPage, !page.isEmpty {
                // 账号还需要在网页上完成设置（例如创建 Xbox 档案、同意条款）
                AuthLog.log("需要打开网页完成账号设置: \(page)")
                throw XboxAuthError.accountSetupRequired(page)
            }
            throw XboxAuthError.invalidResponse("SISU 授权没有返回令牌，返回字段：\(keys)")
        }
        // 服务器不一定回传设备令牌，没有时用我们自己发过去的那份
        return SisuAuthorizeResponse(DeviceToken: raw.DeviceToken ?? deviceToken,
                                     TitleToken: title, UserToken: user, AuthorizationToken: auth)
    }

    private func xstsAuthorize(sisu: SisuAuthorizeResponse, relyingParty: String) async throws -> XboxToken {
        let payload: [String: Any] = [
            "Properties": [
                "SandboxId": "RETAIL",
                "DeviceToken": sisu.DeviceToken,
                "TitleToken": sisu.TitleToken.Token,
                "UserTokens": [sisu.UserToken.Token]
            ],
            "RelyingParty": relyingParty,
            "TokenType": "JWT"
        ]
        let (data, _) = try await signedPost("https://xsts.auth.xboxlive.com/xsts/authorize", json: payload)
        return try decode(XboxToken.self, data, step: "XSTS")
    }

    /// 读取头像等资料；失败时只用 SISU 里的玩家代号
    private func buildProfile(from sisu: SisuAuthorizeResponse) async -> UserProfile {
        var profile = UserProfile(gamertag: sisu.gamertag ?? "Xbox Player", xuid: sisu.xuid, avatarURL: nil, email: credentials.profile?.email)
        do {
            let web = try await xstsAuthorize(sisu: sisu, relyingParty: "http://xboxlive.com")
            webToken = web
            guard let uhs = web.DisplayClaims?.xui?.first?["uhs"] ?? sisu.userHash else { return profile }
            var request = URLRequest(url: URL(string: "https://profile.xboxlive.com/users/me/profile/settings?settings=GameDisplayPicRaw,Gamertag,ModernGamertag")!)
            request.setValue("XBL3.0 x=\(uhs);\(web.Token)", forHTTPHeaderField: "Authorization")
            request.setValue("3", forHTTPHeaderField: "x-xbl-contract-version")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, _) = try await send(request)
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let users = obj["profileUsers"] as? [[String: Any]],
               let settings = users.first?["settings"] as? [[String: Any]] {
                for s in settings {
                    guard let id = s["id"] as? String, let value = s["value"] as? String, !value.isEmpty else { continue }
                    switch id {
                    case "GameDisplayPicRaw": profile.avatarURL = URL(string: value)
                    case "ModernGamertag": profile.gamertag = value
                    case "Gamertag": if sisu.gamertag == nil { profile.gamertag = value }
                    default: break
                    }
                }
            }
        } catch {
            // 资料读取失败不影响使用
        }
        return profile
    }

    // MARK: HTTP

    private func tokenRequest(_ form: [String: String]) async throws -> MsaTokenResponse {
        var request = URLRequest(url: URL(string: "https://login.live.com/oauth20_token.srf")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store, must-revalidate, no-cache", forHTTPHeaderField: "Cache-Control")
        request.httpBody = Data(FormEncoding.encode(form).utf8)
        let (data, _) = try await send(request)
        return try decode(MsaTokenResponse.self, data, step: "换取令牌")
    }

    private func signedPost(_ urlString: String, json: [String: Any]) async throws -> (Data, HTTPURLResponse) {
        let url = URL(string: urlString)!
        let body = try JSONSerialization.data(withJSONObject: json)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "x-xbl-contract-version")
        request.setValue("no-store, must-revalidate, no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue(try signer.signatureHeader(url: url, body: body), forHTTPHeaderField: "Signature")
        return try await send(request)
    }

    /// 解析 JSON；失败时把哪一步、缺了哪个字段带进错误提示，并把返回内容打到控制台
    private func decode<T: Decodable>(_ type: T.Type, _ data: Data, step: String) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
            AuthLog.log("\(step) 解析失败: \(error)\n返回内容: \(body.prefix(2000))")
            var reason = "\(error)"
            if case DecodingError.keyNotFound(let key, _) = error { reason = "缺少字段 \(key.stringValue)" }
            else if case DecodingError.typeMismatch(_, let ctx) = error { reason = "字段类型不对 \(ctx.codingPath.map(\.stringValue).joined(separator: "."))" }
            else if case DecodingError.dataCorrupted = error { reason = "不是 JSON" }
            throw XboxAuthError.invalidResponse("\(step)：\(reason)")
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw XboxAuthError.invalidResponse("no http") }
        AuthLog.log("\(request.httpMethod ?? "GET") \(request.url?.host ?? "")\(request.url?.path ?? "") → \(http.statusCode)")
        guard (200..<300).contains(http.statusCode) else {
            let xerr = http.value(forHTTPHeaderField: "X-Err")
                ?? (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["XErr"].map { "\($0)" }
            switch xerr {
            case "2148916233": throw XboxAuthError.noXboxAccount
            case "2148916236", "2148916237", "2148916238": throw XboxAuthError.childAccount
            case "2148916235": throw XboxAuthError.regionUnsupported
            default:
                throw XboxAuthError.http(status: http.statusCode,
                                         url: request.url?.absoluteString ?? "",
                                         body: String(data: data, encoding: .utf8) ?? "",
                                         xerr: xerr)
            }
        }
        return (data, http)
    }
}

/// application/x-www-form-urlencoded 编码
enum FormEncoding {
    private static let allowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    static func encode(_ form: [String: String]) -> String {
        form.sorted { $0.key < $1.key }
            .map { "\(escape($0.key))=\(escape($0.value))" }
            .joined(separator: "&")
    }

    static func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

/// 登录过程日志（在 Xcode 底部控制台里搜索 [Auth]）
enum AuthLog {
    static func log(_ message: String) {
        debugLog("[Auth] \(message)")
    }
}

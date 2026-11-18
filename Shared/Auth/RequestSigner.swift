import Foundation
import CryptoKit

/// Xbox Live 请求签名（ProofOfPossession）。
/// 签名格式对照开源实现 xal-node（xal.ts 的 sign 方法）：
///
/// 被签名数据：Int32BE(1) | 0x00 | UInt64BE(windowsTimestamp) | 0x00 |
///             "POST" | 0x00 | path | 0x00 | authorizationToken | 0x00 | body | 0x00
/// 签名头：     Int32BE(1) | UInt64BE(windowsTimestamp) | ECDSA-P256-SHA256 签名（r||s，64 字节），Base64 编码
struct RequestSigner {
    let privateKey: P256.Signing.PrivateKey

    init(privateKey: P256.Signing.PrivateKey) {
        self.privateKey = privateKey
    }

    /// Windows FILETIME：从 1601-01-01 起的 100 纳秒数（精度到秒）
    static func windowsTimestamp(for date: Date) -> UInt64 {
        let seconds = UInt64(max(0, date.timeIntervalSince1970.rounded(.down)))
        return (seconds + 11_644_473_600) * 10_000_000
    }

    static func signingPayload(method: String = "POST",
                               path: String,
                               authorizationToken: String,
                               body: Data,
                               timestamp: UInt64) -> Data {
        var w = ByteWriter(capacity: 32 + path.utf8.count + authorizationToken.utf8.count + body.count)
        w.i32BE(1)
        w.u8(0)
        w.u64BE(timestamp)
        w.u8(0)
        w.bytes(Data(method.utf8)); w.u8(0)
        w.bytes(Data(path.utf8)); w.u8(0)
        w.bytes(Data(authorizationToken.utf8)); w.u8(0)
        w.bytes(body); w.u8(0)
        return w.data
    }

    /// 生成 `Signature` 请求头的值
    func signatureHeader(url: URL, authorizationToken: String = "", body: Data, date: Date = Date()) throws -> String {
        let ts = RequestSigner.windowsTimestamp(for: date)
        let payload = RequestSigner.signingPayload(path: url.path, authorizationToken: authorizationToken, body: body, timestamp: ts)
        let signature = try privateKey.signature(for: payload)
        var header = ByteWriter(capacity: 76)
        header.i32BE(1)
        header.u64BE(ts)
        header.bytes(signature.rawRepresentation)
        return header.data.base64EncodedString()
    }

    /// 公钥的 JWK 表示（ProofKey）
    var proofKey: [String: String] {
        let raw = privateKey.publicKey.rawRepresentation   // x(32) || y(32)
        let x = raw.prefix(32)
        let y = raw.suffix(32)
        return [
            "use": "sig",
            "alg": "ES256",
            "kty": "EC",
            "crv": "P-256",
            "x": Data(x).base64URLEncodedString(),
            "y": Data(y).base64URLEncodedString()
        ]
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        self.init(base64Encoded: s)
    }

    static func random(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        var generator = SystemRandomNumberGenerator()
        for i in 0..<count { bytes[i] = UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes)
    }
}

/// PKCE code challenge
struct CodeChallenge {
    let verifier: String
    let challenge: String
    let method = "S256"

    static func generate() -> CodeChallenge {
        let verifier = Data.random(count: 32).base64URLEncodedString()
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return CodeChallenge(verifier: verifier, challenge: Data(digest).base64URLEncodedString())
    }
}

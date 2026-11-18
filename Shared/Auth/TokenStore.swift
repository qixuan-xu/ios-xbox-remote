import Foundation
import Security

/// 简单的 Keychain 封装（通用密码项）
enum Keychain {
    private static let service = "com.example.xboxremote.auth"

    static func set(_ data: Data, for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func get(_ key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// 需要长期保存的登录信息。短期令牌（SISU / XSTS / 串流令牌）每次启动重新获取。
struct StoredCredentials: Codable {
    /// 设备签名私钥（P-256 raw）
    var privateKey: Data
    var deviceId: String
    var serialNumber: String
    var refreshToken: String?
    var userId: String?
    var profile: UserProfile?
}

enum TokenStore {
    private static let key = "credentials.v1"

    static func load() -> StoredCredentials? {
        guard let data = Keychain.get(key) else { return nil }
        return try? JSONDecoder().decode(StoredCredentials.self, from: data)
    }

    static func save(_ credentials: StoredCredentials) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        Keychain.set(data, for: key)
    }

    static func clear() {
        Keychain.delete(key)
    }
}

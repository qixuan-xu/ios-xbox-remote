import SwiftUI

enum ConsoleKind: String, Codable, Hashable {
    case seriesX, seriesS, one, unknown

    /// 从服务器返回的 consoleType 字符串推断型号
    init(consoleType: String) {
        let t = consoleType.lowercased()
        if t.contains("scarlett") || t.contains("seriesx") || t.contains("anaconda") {
            self = .seriesX
        } else if t.contains("lockhart") || t.contains("seriess") {
            self = .seriesS
        } else if t.contains("xboxone") || t.contains("edmonton") || t.contains("durango") || t.contains("one") {
            self = .one
        } else {
            self = .unknown
        }
    }

    var displayName: String {
        switch self {
        case .seriesX: return "Xbox Series X"
        case .seriesS: return "Xbox Series S"
        case .one: return "Xbox One"
        case .unknown: return "Xbox"
        }
    }
}

enum ConsoleStatus: String, Codable, Hashable {
    case online, standby, offline

    init(powerState: String) {
        switch powerState.lowercased() {
        case "on": self = .online
        case "connectedstandby", "standby": self = .standby
        default: self = .offline
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .online: return "在线"
        case .standby: return "睡眠中"
        case .offline: return "离线"
        }
    }

    var color: Color {
        switch self {
        case .online: return Theme.Palette.accent
        case .standby: return Theme.Palette.amber
        case .offline: return Theme.Palette.neutral
        }
    }

    var canStream: Bool { self != .offline }
}

struct Console: Identifiable, Hashable, Codable {
    var id: String            // serverId
    var name: String          // deviceName
    var kind: ConsoleKind
    var status: ConsoleStatus
    var consoleTypeRaw: String
    var outOfHomeWarning: Bool = false
    var wirelessWarning: Bool = false
    var isDevKit: Bool = false
    var region: String? = nil

    static let demo: [Console] = [
        Console(id: "demo-x", name: "客厅", kind: .seriesX, status: .online, consoleTypeRaw: "Scarlett", region: "WestUS"),
        Console(id: "demo-s", name: "书房", kind: .seriesS, status: .standby, consoleTypeRaw: "Lockhart", region: "WestUS"),
        Console(id: "demo-one", name: "旧主机", kind: .one, status: .offline, consoleTypeRaw: "XboxOneS", region: "WestUS")
    ]
}

struct RecentSession: Identifiable, Codable, Hashable {
    var id = UUID()
    var consoleId: String
    var consoleName: String
    var kind: ConsoleKind
    var startedAt: Date
    var duration: TimeInterval
}

enum StreamResolution: String, Codable, CaseIterable, Hashable {
    case auto, p720, p1080

    var label: LocalizedStringKey {
        switch self {
        case .auto: return "自动"
        case .p720: return "720p"
        case .p1080: return "1080p"
        }
    }

    var dimensions: (width: Int, height: Int) {
        switch self {
        case .p720: return (1280, 720)
        case .auto, .p1080: return (1920, 1080)
        }
    }
}

enum VideoFillMode: String, Codable, CaseIterable, Hashable {
    case fit, fill
    var label: LocalizedStringKey { self == .fit ? "适应" : "填满" }
}

enum TriggerMode: String, Codable, CaseIterable, Hashable {
    case instant, ramp
    var label: LocalizedStringKey { self == .instant ? "立即满值" : "按住渐增" }
}

struct UserProfile: Codable, Hashable {
    var gamertag: String
    var xuid: String?
    var avatarURL: URL?
    var email: String?

    static let demo = UserProfile(gamertag: "Player One", xuid: nil, avatarURL: nil, email: "player@example.com")

    var initials: String {
        let parts = gamertag.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    /// 打码显示的邮箱
    var maskedEmail: String? {
        guard let email, let at = email.firstIndex(of: "@") else { return nil }
        let name = email[..<at]
        let domain = email[at...]
        guard let first = name.first else { return email }
        return "\(first)\(String(repeating: "•", count: max(2, min(6, name.count - 1))))\(domain)"
    }
}

import SwiftUI

/// 识别语言（游戏里说的是什么语言）
enum CaptionLanguage: String, Codable, CaseIterable, Hashable, Identifiable {
    case english, japanese, korean, spanish, french, german, chinese

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .english: return "英语"
        case .japanese: return "日语"
        case .korean: return "韩语"
        case .spanish: return "西班牙语"
        case .french: return "法语"
        case .german: return "德语"
        case .chinese: return "中文"
        }
    }

    /// 语音识别用的地区标识
    var localeIdentifier: String {
        switch self {
        case .english: return "en-US"
        case .japanese: return "ja-JP"
        case .korean: return "ko-KR"
        case .spanish: return "es-ES"
        case .french: return "fr-FR"
        case .german: return "de-DE"
        case .chinese: return "zh-CN"
        }
    }

    /// 翻译用的语言代码
    var languageCode: String {
        switch self {
        case .english: return "en"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .spanish: return "es"
        case .french: return "fr"
        case .german: return "de"
        case .chinese: return "zh-Hans"
        }
    }

    /// 识别语言本身就是中文时不需要翻译
    var needsTranslation: Bool { self != .chinese }
}

/// 字幕显示方式
enum CaptionDisplay: String, Codable, CaseIterable, Hashable {
    case bilingual, translated, original

    var label: LocalizedStringKey {
        switch self {
        case .bilingual: return "双语"
        case .translated: return "只看中文"
        case .original: return "只看原文"
        }
    }
}

/// 一句已经说完的字幕
struct CaptionLine: Identifiable, Equatable {
    let id = UUID()
    var original: String
    var translated: String?
    var finishedAt: Date
}

/// 分句规则（纯函数，可单元测试）
enum CaptionSegmenter {
    /// 停顿多久算一句话说完
    static let pause: TimeInterval = 1.2
    /// 单次识别任务的最长时间，超过就换新任务，避免系统识别时长上限
    static let maxTaskDuration: TimeInterval = 50

    /// 当前这段识别文字是否应该定稿成一句
    static func shouldFinalize(text: String, lastUpdate: Date, taskStart: Date, now: Date) -> Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasText && now.timeIntervalSince(lastUpdate) >= pause { return true }
        if now.timeIntervalSince(taskStart) >= maxTaskDuration { return true }
        return false
    }

    /// 一句话最长多少字符，超过就在空格处强制断开
    static let maxSentenceLength = 100

    /// 在一段还没定稿的文字里找断句位置（返回断开处的字符数）：
    /// 1. 有句末标点（. ? ! 。 ？ ！）且后面已经有新内容时，在最后一个这样的标点后断开；
    /// 2. 否则超过 maxSentenceLength 时，在最后一个空格处断开（没有空格就直接截断）。
    static func splitPoint(in text: String) -> Int? {
        let chars = Array(text)
        let terminators: Set<Character> = [".", "?", "!", "。", "？", "！"]
        var lastBoundary: Int?
        for (i, c) in chars.enumerated() where terminators.contains(c) {
            let after = chars[(i + 1)...]
            if after.contains(where: { !$0.isWhitespace }) { lastBoundary = i + 1 }
        }
        if let lastBoundary { return lastBoundary }
        guard chars.count > maxSentenceLength else { return nil }
        if let space = chars[..<maxSentenceLength].lastIndex(where: { $0 == " " }), space > 0 { return space }
        return maxSentenceLength
    }

    /// 保留最近几句，避免字幕越堆越多
    static func trimmed(_ lines: [CaptionLine], keep: Int = 3) -> [CaptionLine] {
        lines.count > keep ? Array(lines.suffix(keep)) : lines
    }
}

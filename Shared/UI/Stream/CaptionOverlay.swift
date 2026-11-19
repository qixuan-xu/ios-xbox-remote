import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// 画面下方的字幕条：双语时中文大字在上、原文小字在下
struct CaptionOverlay: View {
    @ObservedObject var engine: CaptionEngine
    var display: CaptionDisplay
    var fontScale: Double

    private var translationAvailable: Bool {
        if #available(macOS 15.0, iOS 18.0, *) { return true }
        return false
    }
    private var showTranslation: Bool { translationAvailable && engine.language.needsTranslation && display != .original }
    private var showOriginal: Bool { display != .translated || !showTranslation }

    var body: some View {
        VStack {
            Spacer()
            content
                .padding(.bottom, 36)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .allowsHitTesting(false)
        .animation(Theme.Motion.gentle, value: engine.isVisible)
        .animation(Theme.Motion.gentle, value: engine.lines)
        .animation(Theme.Motion.gentle, value: engine.partial)
        .modifier(CaptionTranslationHost(engine: engine, enabled: showTranslation))
    }

    @ViewBuilder
    private var content: some View {
        if case .error(let message) = engine.status {
            captionBox {
                Label { Text(verbatim: message) } icon: { Image(systemName: "captions.bubble") }
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        } else if engine.isVisible, !(engine.lines.isEmpty && engine.partial.isEmpty) {
            captionBox {
                VStack(spacing: 6) {
                    // 最近说完的一句
                    if let line = engine.lines.last {
                        entry(original: line.original, translated: line.translated, pending: showTranslation && line.translated == nil)
                    }
                    // 正在说的一句（只有原文，说完后才翻译）
                    if !engine.partial.isEmpty {
                        Text(verbatim: engine.partial)
                            .font(.system(size: 15 * fontScale, weight: .regular))
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.head)   // 只显示最新识别到的部分，不会撑开、来回跳
                            .transition(.opacity)
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    @ViewBuilder
    private func entry(original: String, translated: String?, pending: Bool) -> some View {
        VStack(spacing: 3) {
            if showTranslation {
                if let translated {
                    Text(verbatim: translated)
                        .font(.system(size: 22 * fontScale, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                } else if pending {
                    Text("翻译中…")
                        .font(.system(size: 15 * fontScale))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            if showOriginal {
                Text(verbatim: original)
                    .font(.system(size: (showTranslation ? 15 : 21) * fontScale,
                                  weight: showTranslation ? .regular : .semibold))
                    .foregroundStyle(showTranslation ? Theme.Palette.textSecondary : Theme.Palette.textPrimary)
                    .multilineTextAlignment(.center)
            }
        }
        .lineLimit(3)
    }

    private func captionBox<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(maxWidth: 900)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }
}

/// 用系统翻译框架（macOS 15 / iOS 18 起）把定稿的句子翻译成简体中文
struct CaptionTranslationHost: ViewModifier {
    @ObservedObject var engine: CaptionEngine
    var enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        #if canImport(Translation)
        if #available(macOS 15.0, iOS 18.0, *), enabled {
            content.translationTask(
                TranslationSession.Configuration(source: Locale.Language(identifier: engine.language.languageCode),
                                                 target: Locale.Language(identifier: "zh-Hans"))
            ) { session in
                let stream = await engine.makeTranslationStream()
                for await line in stream {
                    do {
                        let response = try await session.translate(line.original)
                        await engine.setTranslation(response.targetText, for: line.id)
                    } catch {
                        await engine.translationFailed(error)
                    }
                }
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

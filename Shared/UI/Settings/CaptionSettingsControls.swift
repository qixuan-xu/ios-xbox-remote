import SwiftUI

/// 字幕设置：开关、识别语言、显示方式、字号（快捷菜单和设置页共用）
struct CaptionSettingsControls: View {
    var compact: Bool
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Toggle(isOn: $settings.captionsEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("实时字幕")
                        .font(compact ? Theme.Typography.callout : Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    if !compact {
                        Text("识别游戏和队友的语音，并翻译成中文")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
            }
            .tint(Theme.Palette.accent)

            HStack {
                Text("游戏语言")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Palette.textSecondary)
                Spacer()
                Picker("", selection: $settings.captionLanguage) {
                    ForEach(CaptionLanguage.allCases) { language in
                        Text(language.label).tag(language)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 140)
            }

            Text("显示")
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Palette.textSecondary)
            SegmentedPicker(options: CaptionDisplay.allCases.map { ($0, $0.label) },
                            selection: $settings.captionDisplay)

            HStack {
                Text("字号")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Palette.textSecondary)
                Slider(value: $settings.captionFontScale, in: 0.8...1.6)
                    .tint(Theme.Palette.accent)
            }

            if !compact {
                Text("第一次打开时，系统会请求「语音识别」和「录屏与系统录音」权限。只用来获取本 App 播放的声音，不会录制你的屏幕。首次翻译可能需要下载语言包。")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

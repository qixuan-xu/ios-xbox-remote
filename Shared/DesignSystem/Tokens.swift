import SwiftUI

/// 设计令牌：颜色、圆角、间距、字体、阴影、动效。
/// 整个 App 只从这里取视觉参数，保证风格一致。
enum Theme {

    enum Palette {
        /// 近黑背景
        static let background = Color(hex: 0x0A0B0D)
        static let backgroundRaised = Color(hex: 0x111317)

        /// 玻璃表面上的轻微白色填充
        static let surfaceFill = Color.white.opacity(0.06)
        static let surfaceFillPressed = Color.white.opacity(0.10)

        /// 强调色（Xbox 绿的提亮版），只用于主按钮、在线状态和焦点光晕
        static let accent = Color(hex: 0x2BD45E)
        static let accentDeep = Color(hex: 0x107C10)

        static let amber = Color(hex: 0xE8B04A)
        static let danger = Color(hex: 0xFF5A5F)
        static let neutral = Color(hex: 0x8A8F98)

        static let textPrimary = Color.white.opacity(0.92)
        static let textSecondary = Color.white.opacity(0.60)
        static let textTertiary = Color.white.opacity(0.38)

        static let hairline = Color.white.opacity(0.10)
        static let hairlineStrong = Color.white.opacity(0.22)

        /// 环境光斑
        static let ambientGreen = Color(hex: 0x0E3B22)
        static let ambientGraphite = Color(hex: 0x1C2230)
        static let ambientTeal = Color(hex: 0x0B2A2E)

        /// 手柄按键按下时的柔光颜色（默认不铺色）
        static let buttonA = Color(hex: 0x4BD27A)
        static let buttonB = Color(hex: 0xF0565C)
        static let buttonX = Color(hex: 0x4A8DF0)
        static let buttonY = Color(hex: 0xF2C14E)
    }

    enum Radius {
        static let card: CGFloat = 24
        static let button: CGFloat = 16
        static let small: CGFloat = 12
        static let tiny: CGFloat = 8
    }

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Typography {
        /// 大标题 34，Display，紧字距
        static let largeTitle = Font.system(size: 34, weight: .bold, design: .default)
        static let title = Font.system(size: 22, weight: .semibold, design: .default)
        static let headline = Font.system(size: 17, weight: .semibold, design: .default)
        static let body = Font.system(size: 17, weight: .regular, design: .default)
        static let callout = Font.system(size: 15, weight: .regular, design: .default)
        static let caption = Font.system(size: 13, weight: .regular, design: .default)
        static let captionStrong = Font.system(size: 13, weight: .semibold, design: .default)
        static let overline = Font.system(size: 12, weight: .semibold, design: .default)

        /// 手柄按键字母
        static func controllerGlyph(_ size: CGFloat) -> Font {
            .system(size: size, weight: .semibold, design: .rounded)
        }

        /// 等宽数字（延迟、码率、电量）
        static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
            .system(size: size, weight: weight, design: .default).monospacedDigit()
        }

        /// 步骤编号等大号细体数字
        static func display(_ size: CGFloat, weight: Font.Weight = .thin) -> Font {
            .system(size: size, weight: weight, design: .default).monospacedDigit()
        }
    }

    enum Motion {
        /// 全局统一的弹簧曲线
        static let spring = Animation.spring(response: 0.45, dampingFraction: 0.85)
        static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.82)
        static let gentle = Animation.easeInOut(duration: 0.35)
        static let fade = Animation.easeInOut(duration: 0.25)

        /// 「减弱动态效果」开启时改为淡入淡出
        static func adaptive(_ reduceMotion: Bool) -> Animation {
            reduceMotion ? fade : spring
        }
    }

    enum Shadow {
        static let cardColor = Color.black.opacity(0.40)
        static let cardRadius: CGFloat = 30
        static let cardY: CGFloat = 12
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

extension Font {
    /// 标题使用的紧字距版本
    static let xrLargeTitle = Theme.Typography.largeTitle
}

extension View {
    /// 大标题样式：Display 字号 + 紧字距
    func largeTitleStyle() -> some View {
        self.font(Theme.Typography.largeTitle)
            .tracking(-0.5)
            .foregroundStyle(Theme.Palette.textPrimary)
    }

    func titleStyle() -> some View {
        self.font(Theme.Typography.title)
            .tracking(-0.3)
            .foregroundStyle(Theme.Palette.textPrimary)
    }

    /// 分组标题：小号、大写、灰色、加宽字距
    func overlineStyle() -> some View {
        self.font(Theme.Typography.overline)
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(Theme.Palette.textTertiary)
    }
}

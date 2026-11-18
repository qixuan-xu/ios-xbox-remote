import SwiftUI

/// 设置指南：4 页横向分页卡片
struct SetupGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @GestureState private var dragOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pages: [GuidePage] = [
        GuidePage(number: "01", illustration: .remote,
                  title: "开启远程功能",
                  detail: "在主机上打开 设置 > 设备与连接 > 远程功能，勾选「启用远程功能」。"),
        GuidePage(number: "02", illustration: .power,
                  title: "电源模式选择「睡眠」",
                  detail: "设置 > 常规 > 电源选项，选择「睡眠」。这样主机关机后也能被远程唤醒。"),
        GuidePage(number: "03", illustration: .account,
                  title: "使用同一个账号",
                  detail: "主机和这个 App 需要登录同一个 Microsoft 账号，主机列表里才会出现你的主机。"),
        GuidePage(number: "04", illustration: .network,
                  title: "检查网络",
                  detail: "建议主机使用有线网络，手机连接 5GHz Wi-Fi。外出时上行带宽至少 10 Mbps。")
    ]

    var body: some View {
        ZStack {
            AmbientBackground(intensity: 0.7)
            VStack(spacing: Theme.Spacing.l) {
                HStack {
                    Text("设置指南").overlineStyle()
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(GlassIconButtonStyle(size: 34))
                    .accessibilityLabel(Text("关闭"))
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.l)

                GeometryReader { geo in
                    let width = geo.size.width
                    HStack(spacing: 0) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                            GuideCard(page: item)
                                .padding(.horizontal, Theme.Spacing.l)
                                .frame(width: width)
                                .scaleEffect(index == page ? 1 : 0.94)
                                .opacity(index == page ? 1 : 0.5)
                        }
                    }
                    .offset(x: -CGFloat(page) * width + dragOffset)
                    .animation(Theme.Motion.adaptive(reduceMotion), value: page)
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .updating($dragOffset) { value, state, _ in state = value.translation.width }
                            .onEnded { value in
                                let threshold = width * 0.18
                                if value.translation.width < -threshold { go(page + 1) }
                                else if value.translation.width > threshold { go(page - 1) }
                            }
                    )
                }

                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? Theme.Palette.textPrimary : Theme.Palette.textTertiary.opacity(0.6))
                            .frame(width: i == page ? 18 : 6, height: 6)
                            .onTapGesture { go(i) }
                    }
                }
                .animation(Theme.Motion.snappy, value: page)

                HStack(spacing: Theme.Spacing.s) {
                    if page > 0 {
                        Button("上一步") { go(page - 1) }
                            .buttonStyle(GhostButtonStyle())
                            .transition(.opacity)
                    }
                    Button(page == pages.count - 1 ? LocalizedStringKey("完成") : LocalizedStringKey("下一步")) {
                        if page == pages.count - 1 { dismiss() } else { go(page + 1) }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.l)
                .animation(Theme.Motion.spring, value: page)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func go(_ index: Int) {
        let clamped = max(0, min(pages.count - 1, index))
        guard clamped != page else { return }
        Haptics.selection()
        page = clamped
    }
}

private struct GuidePage {
    enum Illustration { case remote, power, account, network }
    var number: String
    var illustration: Illustration
    var title: LocalizedStringKey
    var detail: LocalizedStringKey
}

private struct GuideCard: View {
    var page: GuidePage

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            illustration
                .frame(maxWidth: .infinity)
                .frame(height: 170)
                .padding(.top, Theme.Spacing.l)

            Text(page.number)
                .font(Theme.Typography.display(56))
                .foregroundStyle(Theme.Palette.textTertiary)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(page.title).titleStyle()
                Text(page.detail)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glass()
        .cardShadow()
    }

    @ViewBuilder
    private var illustration: some View {
        switch page.illustration {
        case .remote:
            ZStack {
                ConsoleSilhouette(kind: .seriesX).frame(height: 150)
                Image(systemName: "dot.radiowaves.up.forward")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.Palette.accent)
                    .offset(x: 70, y: -50)
            }
        case .power:
            ZStack {
                Circle()
                    .stroke(Theme.Palette.amber.opacity(0.3), lineWidth: 1)
                    .frame(width: 130, height: 130)
                Image(systemName: "moon")
                    .font(.system(size: 46, weight: .ultraLight))
                    .foregroundStyle(Theme.Palette.amber)
            }
        case .account:
            HStack(spacing: Theme.Spacing.l) {
                ConsoleSilhouette(kind: .seriesS).frame(height: 90)
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundStyle(Theme.Palette.accent)
                PhoneGlyph().frame(height: 110)
            }
        case .network:
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(Theme.Palette.accent.opacity(0.35 - Double(i) * 0.1), lineWidth: 1)
                        .frame(width: CGFloat(70 + i * 40), height: CGFloat(70 + i * 40))
                }
                Image(systemName: "wifi")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
        }
    }
}

#Preview {
    SetupGuideView()
}

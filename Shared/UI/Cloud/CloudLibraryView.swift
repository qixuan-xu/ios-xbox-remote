import SwiftUI

/// 云游戏库：搜索 + 海报网格
struct CloudLibraryView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [CloudTitle] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return app.cloudTitles }
        return app.cloudTitles.filter {
            $0.name.localizedCaseInsensitiveContains(q) || ($0.publisher?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    var body: some View {
        ZStack {
            AmbientBackground(intensity: 0.7)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    header
                    searchField

                    switch app.cloudAvailability {
                    case .unknown, .loading:
                        grid(placeholders: 9)
                    case .unavailable(let reason):
                        unavailable(reason)
                    case .available:
                        if query.isEmpty && !app.recentCloudTitles.isEmpty {
                            Text("继续游玩").overlineStyle().padding(.leading, 4)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Theme.Spacing.s) {
                                    ForEach(app.recentCloudTitles) { title in
                                        CloudTitleCard(title: title, width: 120) { play(title) }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        Text(query.isEmpty ? LocalizedStringKey("全部游戏") : LocalizedStringKey("搜索结果"))
                            .overlineStyle().padding(.leading, 4)
                        if filtered.isEmpty {
                            Text("没有找到匹配的游戏")
                                .font(Theme.Typography.callout)
                                .foregroundStyle(Theme.Palette.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Theme.Spacing.xl)
                        } else {
                            LazyVGrid(columns: columns, spacing: Theme.Spacing.m) {
                                ForEach(filtered) { title in
                                    CloudTitleCard(title: title, width: nil) { play(title) }
                                }
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.l)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .task { await app.loadCloudLibrary() }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 104, maximum: 170), spacing: Theme.Spacing.m)]
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("云游戏").largeTitleStyle()
                Text("无需主机，直接从云端串流游戏")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer()
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(GlassIconButtonStyle(size: 34))
                .accessibilityLabel(Text("关闭"))
        }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Palette.textTertiary)
            TextField("搜索游戏", text: $query)
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.Palette.textPrimary)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .frame(height: 44)
        .glass(cornerRadius: 14)
    }

    private func grid(placeholders: Int) -> some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.m) {
            ForEach(0..<placeholders, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.Palette.surfaceFill)
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .shimmer()
            }
        }
        .accessibilityLabel(Text("正在加载游戏"))
    }

    private func unavailable(_ reason: String) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: "cloud.slash")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text("云游戏暂不可用").titleStyle()
            Text(verbatim: reason)
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("重试") { Task { await app.loadCloudLibrary(force: true) } }
                .buttonStyle(OutlineButtonStyle())
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .glass()
    }

    private func play(_ title: CloudTitle) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { app.startCloud(title) }
    }
}

/// 游戏海报卡片：竖版 2:3，加载失败时显示渐变 + 首字母
struct CloudTitleCard: View {
    var title: CloudTitle
    var width: CGFloat?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                CloudPoster(title: title)
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .frame(width: width)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                Text(verbatim: title.name)
                    .font(Theme.Typography.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                    .frame(width: width, alignment: .leading)
            }
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityLabel(Text(verbatim: title.name))
    }
}

/// 海报图片（无图时用名字生成的渐变占位）
struct CloudPoster: View {
    var title: CloudTitle

    var body: some View {
        ZStack {
            placeholder
            if let url = title.posterURL ?? title.tileURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill().transition(.opacity)
                    }
                }
            }
        }
        .clipped()
    }

    private var placeholder: some View {
        let hue = Double(title.name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }) / 360
        return ZStack {
            LinearGradient(colors: [Color(hue: hue, saturation: 0.45, brightness: 0.35),
                                    Color(hue: hue, saturation: 0.55, brightness: 0.12)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(verbatim: String(title.name.prefix(1)))
                .font(.system(size: 34, weight: .thin, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.7))
        }
    }
}

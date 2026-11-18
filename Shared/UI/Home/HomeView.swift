import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var controllers: ControllerManager
    @Environment(\.heroNamespace) private var heroNamespace
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    @State private var scrollOffset: CGFloat = 0
    @State private var showSettings = false
    @State private var showGuide = false
    @State private var renaming: Console?
    @State private var renameText = ""
    @State private var detailConsole: Console?
    @State private var page = 0
    @State private var showCloud = false

    private var isCompact: Bool {
        #if os(iOS)
        return sizeClass == .compact
        #else
        return false
        #endif
    }

    private var collapsed: Bool { scrollOffset < -56 }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    GeometryReader { geo in
                        Color.clear.preference(key: ScrollOffsetKey.self, value: geo.frame(in: .named("homeScroll")).minY)
                    }
                    .frame(height: 0)

                    header
                    ControllerStatusStrip()

                    consolesSection

                    if !app.recentSessions.isEmpty {
                        recentSection
                    }

                    cloudSection
                        .padding(.bottom, Theme.Spacing.xxl)
                }
                .padding(.horizontal, isCompact ? Theme.Spacing.l : Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.m)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .coordinateSpace(name: "homeScroll")
            .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = $0 }
            #if os(iOS)
            .refreshable { await app.refreshConsoles() }
            #endif

            compactBar
                .opacity(collapsed ? 1 : 0)
                .offset(y: collapsed ? 0 : -12)
                .animation(Theme.Motion.snappy, value: collapsed)
        }
        #if os(iOS)
        .sheet(isPresented: $showSettings) {
            SettingsView(isSheet: true)
        }
        #endif
        .onAppear {
            #if os(iOS)
            if DebugLaunch.is("settings") || DebugLaunch.is("editor") { showSettings = true }
            #endif
        }
        .sheet(isPresented: $showCloud) {
            CloudLibraryView()
                #if os(macOS)
                .frame(minWidth: 760, minHeight: 620)
                #endif
        }
        .sheet(isPresented: $showGuide) {
            SetupGuideView()
                #if os(macOS)
                .frame(width: 560, height: 620)
                #endif
        }
        .sheet(item: $detailConsole) { console in
            ConsoleDetailSheet(console: console)
                #if os(macOS)
                .frame(width: 460, height: 420)
                #endif
        }
        .alert("重命名主机", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) { renaming = nil }
            Button("保存") {
                if let renaming { app.rename(renaming, to: renameText) }
                renaming = nil
            }
        } message: {
            Text("只会改变在这台设备上显示的名字。")
        }
    }

    // MARK: 顶部

    private var greeting: LocalizedStringKey {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "早上好"
        case 12..<18: return "下午好"
        default: return "晚上好"
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(Theme.Typography.callout.weight(.medium))
                    .foregroundStyle(Theme.Palette.textSecondary)
                Text(app.profile?.gamertag ?? "Xbox")
                    .largeTitleStyle()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
            #if os(macOS)
            Button {
                Task { await app.refreshConsoles() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(GlassIconButtonStyle(size: 40))
            .help(Text("刷新主机"))
            #endif
            Button {
                openSettings()
            } label: {
                AvatarView(profile: app.profile, size: 46)
            }
            .buttonStyle(CardButtonStyle())
            .accessibilityLabel(Text("设置"))
        }
        .opacity(collapsed ? 0 : 1)
        .animation(Theme.Motion.snappy, value: collapsed)
    }

    private var compactBar: some View {
        HStack {
            Text(app.profile?.gamertag ?? "Xbox")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
            Button { openSettings() } label: { AvatarView(profile: app.profile, size: 30) }
                .buttonStyle(CardButtonStyle())
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Hairline() }
        .allowsHitTesting(collapsed)
    }

    private func openSettings() {
        Haptics.selection()
        #if os(iOS)
        showSettings = true
        #else
        MacActions.openSettings()
        #endif
    }

    // MARK: 主机

    @ViewBuilder
    private var consolesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Text("我的主机").overlineStyle()
                Spacer()
                if app.isLoadingConsoles && app.hasLoadedConsoles {
                    ThinRingSpinner(size: 14, lineWidth: 1.5, tint: Theme.Palette.textTertiary)
                }
            }
            .padding(.leading, 4)

            if !app.hasLoadedConsoles {
                skeleton
            } else if app.consoles.isEmpty {
                EmptyStateView(onGuide: { showGuide = true }, onRetry: { Task { await app.refreshConsoles() } })
            } else if isCompact {
                compactConsoles
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 420), spacing: Theme.Spacing.l)],
                          spacing: Theme.Spacing.l) {
                    ForEach(app.consoles) { console in card(for: console) }
                }
            }
        }
    }

    @ViewBuilder
    private var compactConsoles: some View {
        #if os(iOS)
        VStack(spacing: Theme.Spacing.s) {
            TabView(selection: $page) {
                ForEach(Array(app.consoles.enumerated()), id: \.element.id) { index, console in
                    card(for: console)
                        .padding(.horizontal, 2)
                        .padding(.bottom, 36)   // 给阴影留空间
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 290)
            .padding(.horizontal, -2)

            if app.consoles.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<app.consoles.count, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? Theme.Palette.textPrimary : Theme.Palette.textTertiary.opacity(0.5))
                            .frame(width: i == page ? 16 : 6, height: 6)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, -24)
                .animation(Theme.Motion.snappy, value: page)
            }
        }
        #else
        EmptyView()
        #endif
    }

    private func card(for console: Console) -> some View {
        ConsoleCard(
            console: console,
            displayName: app.displayName(for: console),
            isDefault: settings.defaultConsoleId == console.id,
            isLaunching: app.stream?.console.id == console.id,
            heroNamespace: heroNamespace,
            onPlay: { play(console) }
        )
        .contextMenu {
            Button { renameText = app.displayName(for: console); renaming = console } label: {
                Label("重命名", systemImage: "pencil")
            }
            Button { app.setDefault(console) } label: {
                Label("设为默认", systemImage: "star")
            }
            Button { detailConsole = console } label: {
                Label("查看详情", systemImage: "info.circle")
            }
        }
    }

    private func play(_ console: Console) {
        guard console.status.canStream else {
            Haptics.warning()
            app.toast = ToastMessage(icon: "power", text: String(localized: "主机处于离线状态，请把电源模式设为「睡眠」"), style: .warning,
                                     actionTitle: String(localized: "查看指南"), action: { showGuide = true })
            return
        }
        app.startStream(console)
    }

    private var skeleton: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .fill(Theme.Palette.surfaceFill)
            .frame(height: 230)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)).frame(width: 140, height: 18)
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.05)).frame(width: 90, height: 12)
                }
                .padding(Theme.Spacing.l)
            }
            .shimmer()
            .accessibilityLabel(Text("正在加载主机"))
    }

    // MARK: 最近

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("最近游玩").overlineStyle().padding(.leading, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(app.recentSessions) { session in
                        RecentCard(session: session) {
                            if let console = app.consoles.first(where: { $0.id == session.consoleId }) {
                                play(console)
                            } else {
                                app.showToast(String(localized: "这台主机目前不在列表中"), icon: "questionmark.circle")
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: 云游戏

    private var cloudSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Text("云游戏").overlineStyle()
                Spacer()
                if app.cloudAvailability == .available {
                    Button("全部") { showCloud = true }
                        .buttonStyle(TextButtonStyle(tint: Theme.Palette.accent))
                }
            }
            .padding(.leading, 4)

            switch app.cloudAvailability {
            case .available where !app.cloudTitles.isEmpty:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.s) {
                        ForEach((app.recentCloudTitles.isEmpty ? Array(app.cloudTitles.prefix(10)) : app.recentCloudTitles)) { title in
                            CloudTitleCard(title: title, width: 110) { app.startCloud(title) }
                        }
                        Button { showCloud = true } label: {
                            VStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "square.grid.2x2")
                                    .font(.system(size: 22, weight: .light))
                                Text("游戏库").font(Theme.Typography.caption.weight(.semibold))
                            }
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .frame(width: 110, height: 165)
                            .glass(cornerRadius: 16)
                        }
                        .buttonStyle(CardButtonStyle())
                    }
                    .padding(.vertical, 4)
                }
            default:
                Button { showCloud = true } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        Image(systemName: "cloud")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(Theme.Palette.accent)
                            .frame(width: 48, height: 48)
                            .glass(cornerRadius: 14)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Xbox Cloud Gaming")
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            Group {
                                if case .unavailable(let reason) = app.cloudAvailability {
                                    Text(verbatim: reason)
                                } else {
                                    Text("无需主机，直接从云端串流游戏")
                                }
                            }
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textTertiary)
                            .lineLimit(2)
                        }
                        Spacer()
                        if app.cloudAvailability == .loading {
                            ThinRingSpinner(size: 16, lineWidth: 1.5, tint: Theme.Palette.textTertiary)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                    .padding(Theme.Spacing.m)
                    .glass()
                }
                .buttonStyle(CardButtonStyle())
            }
        }
        .task { await app.loadCloudLibrary() }
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - 头像

struct AvatarView: View {
    var profile: UserProfile?
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Theme.Palette.accentDeep, Theme.Palette.ambientGraphite],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(profile?.initials ?? "?")
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Palette.textPrimary)
            if let url = profile?.avatarURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
                .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }
}

// MARK: - 最近游玩小卡片

private struct RecentCard: View {
    var session: RecentSession
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                ConsoleSilhouette(kind: session.kind, lineWidth: 0.9)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.consoleName)
                        .font(Theme.Typography.callout.weight(.semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(Self.durationText(session.duration))
                            .font(Theme.Typography.mono(12))
                        Text(verbatim: "·")
                        Text(Self.relativeText(session.startedAt))
                            .font(Theme.Typography.caption)
                    }
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1)
                }
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.Palette.accent)
                    .padding(.leading, 4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glass(cornerRadius: 18)
        }
        .buttonStyle(CardButtonStyle())
    }

    static func relativeText(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    static func durationText(_ t: TimeInterval) -> String {
        let minutes = Int(t / 60)
        if minutes < 60 { return String(localized: "\(max(1, minutes)) 分钟") }
        return String(localized: "\(minutes / 60) 小时 \(minutes % 60) 分")
    }
}

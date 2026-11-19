import SwiftUI
#if os(macOS)
import AppKit
#endif

enum AppPhase: Equatable {
    case launching
    case signedOut
    case signedIn
}

enum SignInState: Equatable {
    case idle
    case preparing
    case awaitingWeb
    case finishing
    case done
}

/// 全局状态：登录、主机列表、当前串流、提示条
@MainActor
final class AppState: ObservableObject {
    @Published var phase: AppPhase = .launching
    @Published private(set) var profile: UserProfile?
    @Published private(set) var consoles: [Console] = []
    @Published private(set) var isLoadingConsoles = false
    @Published private(set) var hasLoadedConsoles = false
    @Published private(set) var recentSessions: [RecentSession] = []
    @Published var stream: StreamController?
    @Published var toast: ToastMessage?
    @Published var isDemoMode = false

    // 云游戏
    @Published private(set) var cloudTitles: [CloudTitle] = []
    @Published private(set) var recentCloudTitles: [CloudTitle] = []
    @Published private(set) var cloudAvailability: CloudAvailability = .unknown

    // 登录
    @Published var signInState: SignInState = .idle
    @Published var pendingSignIn: PendingSignIn?
    @Published var showLoginSheet = false

    let settings = AppSettings()
    let auth = XalAuthenticator()

    private let recentKey = "recentSessions.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: recentKey),
           let list = try? JSONDecoder().decode([RecentSession].self, from: data) {
            recentSessions = list
        }
    }

    // MARK: 启动

    func bootstrap() async {
        if DebugLaunch.demo {
            await runDebugLaunch()
            return
        }
        let started = Date()
        var nextPhase: AppPhase = .signedOut
        if await auth.hasStoredLogin {
            profile = await auth.storedProfile
            do {
                profile = try await auth.refresh()
                nextPhase = .signedIn
            } catch let error as XboxAuthError {
                if case .http(let status, _, _, _) = error, status >= 500 {
                    // 网络或服务问题：保留登录，进主页后再重试
                    nextPhase = profile == nil ? .signedOut : .signedIn
                } else {
                    nextPhase = .signedOut
                }
            } catch {
                // 离线等网络错误：仍然进入主页，主机列表加载时再提示
                nextPhase = profile == nil ? .signedOut : .signedIn
            }
        }
        // 启动页至少停留 0.9 秒，让过渡更从容
        let elapsed = Date().timeIntervalSince(started)
        if elapsed < 0.9 { try? await Task.sleep(nanoseconds: UInt64((0.9 - elapsed) * 1_000_000_000)) }
        withAnimation(Theme.Motion.spring) { phase = nextPhase }
        if nextPhase == .signedIn { await refreshConsoles() }
    }

    /// 截图用：直接进入演示模式并跳到指定页面
    private func runDebugLaunch() async {
        let screen = DebugLaunch.screen ?? "home"
        if screen == "welcome" || screen == "guide" {
            phase = .signedOut
            return
        }
        enterDemoMode()
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        switch screen {
        case "connecting", "stream", "menu":
            guard let console = consoles.first else { return }
            startStream(console)
            if screen == "menu" {
                try? await Task.sleep(nanoseconds: 4_500_000_000)
                stream?.isMenuOpen = true
            }
        default:
            break
        }
    }

    // MARK: 登录

    func beginSignIn() {
        guard signInState == .idle || signInState == .done else { return }
        signInState = .preparing
        Task {
            do {
                let pending = try await auth.beginSignIn()
                pendingSignIn = pending
                signInState = .awaitingWeb
                showLoginSheet = true
            } catch {
                signInState = .idle
                showError(error, retry: { [weak self] in self?.beginSignIn() })
            }
        }
    }

    func handleLoginCallback(_ url: URL) {
        guard let pending = pendingSignIn else { return }
        showLoginSheet = false
        signInState = .finishing
        Task {
            do {
                let profile = try await auth.completeSignIn(pending, callbackURL: url)
                self.profile = profile
                pendingSignIn = nil
                signInState = .done
                Haptics.success()
                try? await Task.sleep(nanoseconds: 550_000_000)
                isDemoMode = false
                withAnimation(Theme.Motion.spring) { phase = .signedIn }
                signInState = .idle
                await refreshConsoles()
            } catch {
                signInState = .idle
                showError(error, retry: { [weak self] in self?.beginSignIn() })
            }
        }
    }

    func cancelSignIn() {
        showLoginSheet = false
        pendingSignIn = nil
        signInState = .idle
    }

    func enterDemoMode() {
        isDemoMode = true
        profile = .demo
        withAnimation(Theme.Motion.spring) { phase = .signedIn }
        Task { await refreshConsoles() }
    }

    func signOut() {
        stream?.cancel()
        stream = nil
        Task { await auth.signOut() }
        profile = nil
        consoles = []
        hasLoadedConsoles = false
        isDemoMode = false
        withAnimation(Theme.Motion.spring) { phase = .signedOut }
    }

    // MARK: 主机

    func refreshConsoles() async {
        guard !isLoadingConsoles else { return }
        isLoadingConsoles = true
        defer { isLoadingConsoles = false }

        if isDemoMode {
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation(Theme.Motion.spring) {
                consoles = Console.demo
                hasLoadedConsoles = true
            }
            return
        }
        do {
            let creds = try await auth.streamingCredentials(offering: "xhome")
            let client = GssvClient(baseURL: creds.baseURL, token: creds.gsToken, resolution: settings.resolution)
            var list = try await client.consoles()
            for i in list.indices { list[i].region = creds.regionName }
            // 默认主机排在最前
            if let defaultId = settings.defaultConsoleId, let idx = list.firstIndex(where: { $0.id == defaultId }) {
                list.insert(list.remove(at: idx), at: 0)
            }
            withAnimation(Theme.Motion.spring) {
                consoles = list
                hasLoadedConsoles = true
            }
        } catch {
            hasLoadedConsoles = true
            showError(error, retry: { [weak self] in Task { await self?.refreshConsoles() } })
        }
    }

    func displayName(for console: Console) -> String {
        settings.customConsoleNames[console.id] ?? console.name
    }

    func rename(_ console: Console, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == console.name {
            settings.customConsoleNames.removeValue(forKey: console.id)
        } else {
            settings.customConsoleNames[console.id] = trimmed
        }
        objectWillChange.send()
    }

    func setDefault(_ console: Console) {
        settings.defaultConsoleId = console.id
        if let idx = consoles.firstIndex(of: console) {
            withAnimation(Theme.Motion.spring) { consoles.insert(consoles.remove(at: idx), at: 0) }
        }
        toast = ToastMessage(icon: "star", text: String(localized: "已设为默认主机"), style: .success)
    }

    // MARK: 云游戏

    func loadCloudLibrary(force: Bool = false) async {
        if cloudAvailability == .loading { return }
        if cloudAvailability == .available && !force && !cloudTitles.isEmpty { return }
        cloudAvailability = .loading
        if isDemoMode {
            try? await Task.sleep(nanoseconds: 800_000_000)
            withAnimation(Theme.Motion.spring) {
                cloudTitles = CloudTitle.demo
                recentCloudTitles = Array(CloudTitle.demo.prefix(3))
                cloudAvailability = .available
            }
            return
        }
        do {
            let creds = try await auth.cloudCredentials()
            let client = GssvClient(baseURL: creds.baseURL, token: creds.gsToken, resolution: settings.resolution)
            async let allItems = client.cloudTitles()
            async let recentItems = client.recentCloudTitles()
            let (items, recent) = try await (allItems, recentItems)
            let ids = Array(Set((items + recent).compactMap { $0.details?.productId }))
            let products = try await CatalogClient.products(ids)
            let titles = CatalogClient.merge(items, products: products)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            withAnimation(Theme.Motion.spring) {
                cloudTitles = titles
                recentCloudTitles = CatalogClient.merge(recent, products: products)
                cloudAvailability = titles.isEmpty
                    ? .unavailable(String(localized: "没有可以云端串流的游戏，可能需要 Game Pass Ultimate"))
                    : .available
            }
        } catch XboxAuthError.regionUnsupported {
            cloudAvailability = .unavailable(String(localized: "你所在的地区或账号暂不支持云游戏"))
        } catch {
            cloudAvailability = .unavailable((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func startCloud(_ title: CloudTitle) {
        guard stream == nil else { return }
        let controller = StreamController(cloudTitle: title, auth: isDemoMode ? nil : auth, settings: settings, isDemo: isDemoMode)
        controller.isMuted = !settings.audioEnabled
        Haptics.impact()
        withAnimation(Theme.Motion.spring) { stream = controller }
        controller.start()
    }

    // MARK: 串流

    func startStream(_ console: Console) {
        guard stream == nil else { return }
        var named = console
        named.name = displayName(for: console)
        let controller = StreamController(console: named, auth: isDemoMode ? nil : auth, settings: settings, isDemo: isDemoMode)
        controller.isMuted = !settings.audioEnabled
        controller.onEnded = { [weak self] session in self?.recordSession(session) }
        Haptics.impact()
        withAnimation(Theme.Motion.spring) { stream = controller }
        controller.start()
    }

    func closeStream() {
        guard let stream else { return }
        if stream.phase == .streaming || {
            if case .reconnecting = stream.phase { return true } else { return false }
        }() {
            stream.disconnect()
        } else {
            stream.cancel()
        }
        withAnimation(Theme.Motion.spring) { self.stream = nil }
    }

    private func recordSession(_ session: RecentSession) {
        recentSessions.removeAll { $0.consoleId == session.consoleId }
        recentSessions.insert(session, at: 0)
        if recentSessions.count > 8 { recentSessions = Array(recentSessions.prefix(8)) }
        if let data = try? JSONEncoder().encode(recentSessions) {
            UserDefaults.standard.set(data, forKey: recentKey)
        }
    }

    // MARK: 提示

    func showError(_ error: Error, retry: (() -> Void)? = nil) {
        if case XboxAuthError.accountSetupRequired(let page) = error, let url = URL(string: page) {
            toast = ToastMessage(icon: "person.crop.circle.badge.exclamationmark", text: error.localizedDescription,
                                 style: .warning, actionTitle: String(localized: "打开网页"), action: {
                #if os(iOS)
                UIApplication.shared.open(url)
                #else
                NSWorkspace.shared.open(url)
                #endif
            })
            return
        }
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        toast = ToastMessage(icon: "exclamationmark.triangle", text: text, style: .error,
                             actionTitle: retry == nil ? nil : String(localized: "重试"), action: retry)
        Haptics.error()
    }

    func showToast(_ text: String, icon: String, style: ToastMessage.Style = .info) {
        toast = ToastMessage(icon: icon, text: text, style: style)
    }
}

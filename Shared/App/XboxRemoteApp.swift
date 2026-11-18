import SwiftUI

@main
struct XboxRemoteApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @StateObject private var appState = AppState()
    @StateObject private var controllers = ControllerManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(appState.settings)
                .environmentObject(controllers)
                .preferredColorScheme(.dark)
                .tint(Theme.Palette.accent)
                #if os(macOS)
                .frame(minWidth: 900, minHeight: 600)
                #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)
        .commands { AppCommands(appState: appState) }
        #endif

        #if os(macOS)
        Settings {
            SettingsView(isSheet: false)
                .environmentObject(appState)
                .environmentObject(appState.settings)
                .environmentObject(controllers)
                .preferredColorScheme(.dark)
                .frame(width: 620, height: 680)
        }
        #endif
    }
}

/// 根视图：背景 + 当前阶段页面 + 串流覆盖层 + 提示条
struct RootView: View {
    @EnvironmentObject private var app: AppState
    @Namespace private var heroNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AmbientBackground()

            Group {
                switch app.phase {
                case .launching:
                    SplashView()
                        .transition(.opacity)
                case .signedOut:
                    WelcomeView()
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                case .signedIn:
                    HomeView()
                        .transition(.opacity.combined(with: .scale(scale: 1.02)))
                }
            }
            .environment(\.heroNamespace, heroNamespace)

            if let stream = app.stream {
                StreamContainer(stream: stream)
                    .environment(\.heroNamespace, heroNamespace)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(Theme.Motion.adaptive(reduceMotion), value: app.phase)
        .toastHost($app.toast)
        .task { await app.bootstrap() }
    }
}

// MARK: - 共享的 matchedGeometry 命名空间

private struct HeroNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var heroNamespace: Namespace.ID? {
        get { self[HeroNamespaceKey.self] }
        set { self[HeroNamespaceKey.self] = newValue }
    }
}

extension View {
    /// 有命名空间时才应用 matchedGeometryEffect
    @ViewBuilder
    func hero(_ id: String, in namespace: Namespace.ID?, isSource: Bool = true) -> some View {
        if let namespace {
            self.matchedGeometryEffect(id: id, in: namespace, isSource: isSource)
        } else {
            self
        }
    }
}

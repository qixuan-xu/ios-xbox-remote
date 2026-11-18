import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var app: AppState
    @State private var appeared = false
    @State private var showGuide = false
    @State private var loginModel: WebLoginModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > 700
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: wide ? 60 : 40)

                    ConnectionIllustration()
                        .frame(height: wide ? 220 : 180)
                        .padding(.horizontal, Theme.Spacing.xl)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 16)

                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("在任何地方，玩你的 Xbox")
                            .largeTitleStyle()
                            .fixedSize(horizontal: false, vertical: true)
                        Text("把家里主机的画面串流到这台设备上，延迟低，画质清晰。")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Theme.Spacing.xxl)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)

                    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                        FeatureRow(icon: "dot.radiowaves.left.and.right",
                                   title: "远程游玩家里的主机",
                                   detail: "在家或外出，都能连接你的 Xbox Series X|S 或 Xbox One。")
                        FeatureRow(icon: "hand.tap",
                                   title: "屏幕自带手柄",
                                   detail: "浮动摇杆、滑动连按、自定义布局，只用手机就能玩。")
                        FeatureRow(icon: "gamecontroller",
                                   title: "支持蓝牙手柄",
                                   detail: "连接 Xbox、PlayStation 或 MFi 手柄，屏幕按键自动隐藏。")
                    }
                    .padding(.top, Theme.Spacing.xl)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 8)

                    Spacer(minLength: Theme.Spacing.xxl)

                    VStack(spacing: Theme.Spacing.s) {
                        Button {
                            Haptics.impact()
                            app.beginSignIn()
                        } label: {
                            Text("使用 Microsoft 账号登录")
                        }
                        .buttonStyle(PrimaryButtonStyle(
                            isLoading: app.signInState == .preparing || app.signInState == .finishing,
                            isDone: app.signInState == .done
                        ))
                        .disabled(app.signInState != .idle && app.signInState != .awaitingWeb)

                        HStack(spacing: Theme.Spacing.l) {
                            Button("如何设置主机") { showGuide = true }
                                .buttonStyle(TextButtonStyle())
                            #if DEBUG
                            Button("演示模式") { app.enterDemoMode() }
                                .buttonStyle(TextButtonStyle(tint: Theme.Palette.textTertiary))
                            #endif
                        }
                    }
                    .padding(.bottom, Theme.Spacing.l)
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, Theme.Spacing.l)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
        }
        .onAppear {
            withAnimation(Theme.Motion.adaptive(reduceMotion).delay(0.05)) { appeared = true }
            if DebugLaunch.is("guide") { showGuide = true }
        }
        .onChange(of: app.showLoginSheet) { show in
            if show, let pending = app.pendingSignIn {
                let model = WebLoginModel(startURL: pending.authorizeURL, callbackScheme: XalAuthenticator.redirectScheme)
                model.onCallback = { url in app.handleLoginCallback(url) }
                loginModel = model
            } else if !show {
                loginModel = nil
            }
        }
        .sheet(isPresented: Binding(get: { loginModel != nil && app.showLoginSheet },
                                    set: { if !$0 { app.cancelSignIn() } })) {
            if let loginModel {
                LoginSheet(model: loginModel, onCancel: { app.cancelSignIn() })
                    #if os(macOS)
                    .frame(width: 520, height: 680)
                    #endif
            }
        }
        .sheet(isPresented: $showGuide) {
            SetupGuideView()
                #if os(macOS)
                .frame(width: 560, height: 620)
                #endif
        }
    }
}

private struct FeatureRow: View {
    var icon: String
    var title: LocalizedStringKey
    var detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Theme.Palette.accent)
                .frame(width: 40, height: 40)
                .glass(cornerRadius: 12)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(detail)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// 主机线稿 + 手机线稿，中间一条带流光的虚线
struct ConnectionIllustration: View {
    @State private var phase: CGFloat = 0
    @State private var glow: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            HStack(alignment: .bottom, spacing: 0) {
                ConsoleSilhouette(kind: .seriesX, lineWidth: 1.3)
                    .frame(height: h * 0.92)
                    .background(
                        Circle()
                            .fill(Theme.Palette.accent.opacity(0.18))
                            .blur(radius: 40)
                            .scaleEffect(1.2)
                    )

                ZStack {
                    // 底层虚线
                    LinkLine()
                        .stroke(Theme.Palette.hairlineStrong,
                                style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2, 6]))
                    // 流动的高亮虚线
                    LinkLine()
                        .stroke(Theme.Palette.accent,
                                style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [2, 6], dashPhase: -phase))
                        .mask(
                            LinearGradient(colors: [.clear, .white, .clear],
                                           startPoint: UnitPoint(x: glow - 0.3, y: 0.5),
                                           endPoint: UnitPoint(x: glow + 0.3, y: 0.5))
                        )
                }
                .frame(maxWidth: .infinity)
                .frame(height: h * 0.6)

                PhoneGlyph(lineWidth: 1.3)
                    .frame(height: h * 0.72)
                    .overlay {
                        ControllerGlyph(lineWidth: 0.9)
                            .frame(width: h * 0.24)
                            .opacity(0.8)
                    }
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 16 }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: false)) { glow = 1.3 }
        }
        .accessibilityHidden(true)
    }
}

private struct LinkLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + 8, y: rect.midY + rect.height * 0.15))
        p.addCurve(to: CGPoint(x: rect.maxX - 8, y: rect.midY - rect.height * 0.05),
                   control1: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.minY),
                   control2: CGPoint(x: rect.minX + rect.width * 0.65, y: rect.maxY))
        return p
    }
}

#Preview {
    ZStack {
        AmbientBackground()
        WelcomeView()
    }
    .environmentObject(AppState())
}

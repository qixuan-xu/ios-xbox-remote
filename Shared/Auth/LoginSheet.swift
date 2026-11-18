import SwiftUI
import WebKit

/// 登录网页的状态（加载进度、当前域名），供顶部玻璃导航条显示
final class WebLoginModel: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var progress: Double = 0
    @Published var host: String = ""
    @Published var isLoading = true

    let startURL: URL
    let callbackScheme: String
    var onCallback: ((URL) -> Void)?

    private var observations: [NSKeyValueObservation] = []

    init(startURL: URL, callbackScheme: String) {
        self.startURL = startURL
        self.callbackScheme = callbackScheme
        self.host = startURL.host ?? ""
    }

    func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        #if os(iOS)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        #endif
        observations = [
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async { self?.progress = view.estimatedProgress }
            },
            webView.observe(\.url, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async { self?.host = view.url?.host ?? self?.host ?? "" }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async { self?.isLoading = view.isLoading }
            }
        ]
        webView.load(URLRequest(url: startURL))
        return webView
    }

    // 拦截 ms-xal-...://auth 回调
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, url.scheme?.lowercased() == callbackScheme.lowercased() {
            decisionHandler(.cancel)
            DispatchQueue.main.async { self.onCallback?(url) }
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // 自定义 scheme 被取消时也会走这里，忽略即可
    }
}

/// 登录 sheet：顶部玻璃导航条（取消 + 当前域名 + 2pt 进度线）+ 网页
struct LoginSheet: View {
    @ObservedObject var model: WebLoginModel
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    Button("取消", action: onCancel)
                        .buttonStyle(TextButtonStyle(tint: Theme.Palette.textPrimary))
                    Spacer()
                }
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Palette.accent)
                    Text(model.host)
                        .font(Theme.Typography.captionStrong)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .frame(height: 52)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Theme.Palette.hairline)
                        Rectangle()
                            .fill(Theme.Palette.accent)
                            .frame(width: geo.size.width * model.progress)
                            .opacity(model.isLoading ? 1 : 0)
                            .animation(Theme.Motion.gentle, value: model.progress)
                    }
                }
                .frame(height: 2)
            }

            LoginWebView(model: model)
                .background(Color.white)
        }
        .background(Theme.Palette.background)
    }
}

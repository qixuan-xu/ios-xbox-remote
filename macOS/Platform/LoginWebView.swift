import SwiftUI
import WebKit

struct LoginWebView: NSViewRepresentable {
    let model: WebLoginModel

    func makeNSView(context: Context) -> WKWebView { model.makeWebView() }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

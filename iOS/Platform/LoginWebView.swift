import SwiftUI
import WebKit

struct LoginWebView: UIViewRepresentable {
    let model: WebLoginModel

    func makeUIView(context: Context) -> WKWebView { model.makeWebView() }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

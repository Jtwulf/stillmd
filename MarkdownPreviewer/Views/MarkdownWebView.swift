import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let markdownContent: String
    let baseURL: URL
    @Binding var scrollPosition: CGFloat

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        let userController = WKUserContentController()
        userController.add(context.coordinator, name: "scrollPosition")
        userController.add(context.coordinator, name: "linkClicked")
        config.userContentController = userController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        let html = HTMLTemplate.build(
            markdownContent: markdownContent,
            markedJS: ResourceLoader.loadMarkedJS(),
            highlightJS: ResourceLoader.loadHighlightJS(),
            css: ResourceLoader.loadCSS()
        )
        webView.loadHTMLString(html, baseURL: baseURL)

        context.coordinator.lastContent = markdownContent

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard markdownContent != context.coordinator.lastContent else {
            return
        }
        context.coordinator.lastContent = markdownContent

        let escaped = markdownContent
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "</script>", with: "<\\/script>")

        let js = "updateContent(`\(escaped)`);"
        webView.evaluateJavaScript(js)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let parent: MarkdownWebView
        var lastContent: String = ""

        init(_ parent: MarkdownWebView) {
            self.parent = parent
        }

        // MARK: - WKNavigationDelegate

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               url.scheme == "http" || url.scheme == "https" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        // MARK: - WKScriptMessageHandler

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            switch message.name {
            case "scrollPosition":
                if let position = message.body as? Double {
                    parent.scrollPosition = CGFloat(position)
                }
            case "linkClicked":
                if let urlString = message.body as? String,
                   let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            default:
                break
            }
        }
    }
}

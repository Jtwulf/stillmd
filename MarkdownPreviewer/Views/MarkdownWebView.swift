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
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            // Block javascript: scheme unconditionally
            if url.scheme == "javascript" {
                decisionHandler(.cancel)
                return
            }

            // Only allow non-link-activated navigations (initial load, etc.)
            guard navigationAction.navigationType == .linkActivated else {
                decisionHandler(.allow)
                return
            }

            // External http/https links -> open in system browser
            if url.scheme == "http" || url.scheme == "https" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            // file: links (relative links resolved by baseURL)
            if url.scheme == "file" {
                if FileValidation.isMarkdownFile(url) {
                    // Open .md files in this app (re-open via NSWorkspace targeting our bundle)
                    if let bundleID = Bundle.main.bundleIdentifier {
                        NSWorkspace.shared.open(
                            [url],
                            withApplicationAt: NSWorkspace.shared.urlForApplication(
                                withBundleIdentifier: bundleID)!,
                            configuration: NSWorkspace.OpenConfiguration()
                        )
                    }
                } else {
                    // Non-markdown file: links -> open in Finder/default app
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }

            // Block all other link-activated navigations
            decisionHandler(.cancel)
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
                   let url = URL(string: urlString),
                   url.scheme != "javascript" {
                    NSWorkspace.shared.open(url)
                }
            default:
                break
            }
        }
    }
}

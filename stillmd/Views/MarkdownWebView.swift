import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let markdownContent: String
    let baseURL: URL
    @Binding var scrollPosition: CGFloat
    let themePreference: ThemePreference
    let textScale: Double
    let documentLineNumbersVisible: Bool
    let findQuery: String
    let findRequest: FindRequest?
    @Binding var findStatus: FindStatus
    /// Fires once when the main-frame navigation commits content (`didCommit`), before subresources finish.
    var onInitialNavigationCommitted: (() -> Void)? = nil
    /// Called synchronously at the start of `makeNSView` before `loadHTMLString` (for reveal timing vs WebKit).
    var onWillLoadWebContent: (() -> Void)? = nil

    func makeNSView(context: Context) -> WKWebView {
        onWillLoadWebContent?()

        let config = WKWebViewConfiguration()

        let userController = WKUserContentController()
        userController.add(context.coordinator, name: "scrollPosition")
        userController.add(context.coordinator, name: "linkClicked")
        userController.add(context.coordinator, name: "findResults")
        config.userContentController = userController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        let html = HTMLTemplate.build(
            markdownContent: markdownContent,
            markedJS: ResourceLoader.loadMarkedJS(),
            highlightJS: ResourceLoader.loadHighlightJS(),
            css: ResourceLoader.loadCSS(),
            initialScrollPosition: Double(scrollPosition),
            themePreference: themePreference.rawValue,
            textScale: textScale,
            documentLineNumbersVisible: documentLineNumbersVisible
        )
        webView.loadHTMLString(html, baseURL: baseURL)

        context.coordinator.lastContent = markdownContent
        context.coordinator.lastThemePreference = themePreference.rawValue
        context.coordinator.lastTextScale = textScale
        context.coordinator.lastDocumentLineNumbersVisible = documentLineNumbersVisible
        context.coordinator.lastFindQuery = findQuery

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self

        guard markdownContent != context.coordinator.lastContent else {
            applyAppearanceAndFindState(to: webView, context: context)
            return
        }
        context.coordinator.lastContent = markdownContent

        evaluateJavaScript(
            "updateContent(\(Self.javaScriptStringLiteral(markdownContent)), \(Double(scrollPosition)));",
            in: webView
        )
        applyAppearanceAndFindState(to: webView, context: context)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func applyAppearanceAndFindState(to webView: WKWebView, context: Context) {
        if context.coordinator.lastThemePreference != themePreference.rawValue {
            context.coordinator.lastThemePreference = themePreference.rawValue
            evaluateJavaScript(
                "setThemePreference(\(Self.javaScriptStringLiteral(themePreference.rawValue)));",
                in: webView
            )
        }

        let clampedTextScale = AppPreferences.clampedTextScale(textScale)
        if context.coordinator.lastTextScale != clampedTextScale {
            context.coordinator.lastTextScale = clampedTextScale
            evaluateJavaScript("setTextScale(\(clampedTextScale));", in: webView)
        }

        if context.coordinator.lastDocumentLineNumbersVisible != documentLineNumbersVisible {
            context.coordinator.lastDocumentLineNumbersVisible = documentLineNumbersVisible
            evaluateJavaScript(
                "setDocumentLineNumbersVisible(\(documentLineNumbersVisible));",
                in: webView
            )
        }

        if context.coordinator.lastFindQuery != findQuery {
            context.coordinator.lastFindQuery = findQuery
            evaluateJavaScript(
                "updateFindQuery(\(Self.javaScriptStringLiteral(findQuery)));",
                in: webView
            )
        }

        if let findRequest, context.coordinator.lastFindRequestID != findRequest.id {
            context.coordinator.lastFindRequestID = findRequest.id
            evaluateJavaScript(
                "navigateFind(\(Self.javaScriptStringLiteral(findRequest.direction.rawValue)));",
                in: webView
            )
        }
    }

    private func evaluateJavaScript(_ script: String, in webView: WKWebView) {
        webView.evaluateJavaScript(script)
    }

    private static func javaScriptStringLiteral(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [value], options: [])
        guard
            let data,
            let encoded = String(data: data, encoding: .utf8)
        else {
            return "\"\""
        }

        return String(encoded.dropFirst().dropLast())
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MarkdownWebView
        private var didReportInitialNavigationCommit = false
        var lastContent: String = ""
        var lastThemePreference: String = ThemePreference.system.rawValue
        var lastTextScale: Double = AppPreferences.defaultTextScale
        var lastDocumentLineNumbersVisible: Bool = false
        var lastFindQuery: String = ""
        var lastFindRequestID: Int?

        init(_ parent: MarkdownWebView) {
            self.parent = parent
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            guard !didReportInitialNavigationCommit else { return }
            didReportInitialNavigationCommit = true
            let callback = parent.onInitialNavigationCommitted
            DispatchQueue.main.async {
                callback?()
            }
        }

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
            case "findResults":
                if
                    let result = message.body as? [String: Any],
                    let matchCount = result["matchCount"] as? Int,
                    let currentIndex = result["currentIndex"] as? Int
                {
                    parent.findStatus = FindStatus(
                        matchCount: matchCount,
                        currentIndex: currentIndex
                    )
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

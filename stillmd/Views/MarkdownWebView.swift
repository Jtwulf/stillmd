import AppKit
import SwiftUI
import WebKit

enum StillmdWebViewLogger {
    /// Layout / render diagnostics; omitted in release to reduce stderr churn.
    static func logDiagnostic(_ message: String) {
        #if DEBUG
        fputs("[stillmd][WKWebView] \(message)\n", stderr)
        #endif
    }

    static func log(_ message: String) {
        fputs("[stillmd][WKWebView] \(message)\n", stderr)
    }
}

enum StillmdWebViewConfiguration {
    @MainActor
    static func make(userContentController: WKUserContentController) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        let diagnosticScript = WKUserScript(
            source: """
            window.__stillmdLastError = null;
            window.__stillmdBootPhase = 'document-start';
            window.addEventListener('error', function(event) {
                const message = event?.message || 'unknown script error';
                const filename = event?.filename || 'unknown';
                const line = event?.lineno || 0;
                const column = event?.colno || 0;
                window.__stillmdLastError = `${message} @ ${filename}:${line}:${column}`;
            });
            window.addEventListener('unhandledrejection', function(event) {
                const reason = event?.reason;
                window.__stillmdLastError = reason ? String(reason) : 'unhandled promise rejection';
            });
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(diagnosticScript)
        config.userContentController = userContentController
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        return config
    }
}

/// Hosts a `WKWebView` stretched to the frame SwiftUI/`NSHostingView` assigns.
/// Pure Auto Layout on the container failed for some users; classic autoresizing + `layout()` is more reliable here.
final class StillmdMarkdownWebContainerView: NSView {
    let webView: WKWebView

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        wantsLayer = true
        autoresizingMask = [.width, .height]
        addSubview(webView)
        webView.autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        webView.frame = bounds
        if bounds.width < 1 || bounds.height < 1 {
            StillmdWebViewLogger.logDiagnostic("container laid out with tiny bounds: \(bounds.debugDescription)")
        }
    }
}

struct MarkdownWebView: NSViewRepresentable {
    let markdownContent: String
    /// Precomputed in `PreviewViewModel` when markdown changes; avoids duplicate full-document regex scans.
    let containsMermaidFence: Bool
    let baseURL: URL
    @Binding var scrollPosition: CGFloat
    let themePreference: ThemePreference
    let textScale: Double
    let findQuery: String
    let findRequest: FindRequest?
    @Binding var findStatus: FindStatus
    /// Fires once when the main-frame navigation commits content (`didCommit`), before subresources finish.
    var onInitialNavigationCommitted: (() -> Void)? = nil
    /// Called synchronously at the start of `makeNSView` before `loadHTMLString` (for reveal timing vs WebKit).
    var onWillLoadWebContent: (() -> Void)? = nil

    func makeNSView(context: Context) -> StillmdMarkdownWebContainerView {
        onWillLoadWebContent?()

        let userController = WKUserContentController()
        userController.add(context.coordinator, name: "scrollPosition")
        userController.add(context.coordinator, name: "linkClicked")
        userController.add(context.coordinator, name: "findResults")
        let config = StillmdWebViewConfiguration.make(userContentController: userController)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(true, forKey: "drawsBackground")
        webView.wantsLayer = true

        loadDocument(
            in: webView,
            context: context,
            markdownContent: markdownContent,
            containsMermaidFence: containsMermaidFence
        )

        context.coordinator.lastContent = markdownContent
        context.coordinator.lastThemePreference = themePreference.rawValue
        context.coordinator.lastTextScale = textScale
        context.coordinator.lastFindQuery = findQuery
        context.coordinator.lastContainsMermaidFence = containsMermaidFence

        return StillmdMarkdownWebContainerView(webView: webView)
    }

    /// `NSHostingView` 経由だと提案サイズが 0×0 になり、WKWebView が真っ白になることがある。
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: StillmdMarkdownWebContainerView,
        context: Context
    ) -> CGSize? {
        let floor = CGSize(width: 320, height: 240)
        let r = proposal.replacingUnspecifiedDimensions(by: floor)
        if r.width < 1 || r.height < 1 {
            return floor
        }
        return r
    }

    func updateNSView(_ container: StillmdMarkdownWebContainerView, context: Context) {
        let webView = container.webView
        context.coordinator.parent = self
        guard markdownContent != context.coordinator.lastContent else {
            applyAppearanceAndFindState(to: webView, context: context)
            return
        }

        if containsMermaidFence != context.coordinator.lastContainsMermaidFence {
            context.coordinator.lastContent = markdownContent
            context.coordinator.lastThemePreference = themePreference.rawValue
            context.coordinator.lastTextScale = textScale
            context.coordinator.lastFindQuery = findQuery
            context.coordinator.lastContainsMermaidFence = containsMermaidFence

            loadDocument(
                in: webView,
                context: context,
                markdownContent: markdownContent,
                containsMermaidFence: containsMermaidFence
            )
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

    private func loadDocument(
        in webView: WKWebView,
        context: Context,
        markdownContent: String,
        containsMermaidFence: Bool
    ) {
        let html = HTMLTemplate.build(
            markdownContent: markdownContent,
            markedJS: ResourceLoader.loadMarkedJS(),
            highlightJS: ResourceLoader.loadHighlightJS(),
            css: ResourceLoader.loadCSS(),
            initialScrollPosition: Double(scrollPosition),
            themePreference: themePreference.rawValue,
            textScale: textScale,
            documentBaseURL: baseURL,
            initialFindQuery: findQuery,
            mermaidJS: containsMermaidFence ? ResourceLoader.loadMermaidJS() : nil
        )

        guard let htmlDocument = context.coordinator.htmlDocument else {
            StillmdWebViewLogger.log("temporary HTML document unavailable; falling back to loadHTMLString")
            webView.loadHTMLString(html, baseURL: baseURL)
            return
        }

        do {
            try htmlDocument.write(html: html)
            webView.loadFileURL(htmlDocument.fileURL, allowingReadAccessTo: baseURL)
        } catch {
            StillmdWebViewLogger.log("temporary HTML write failed: \(error.localizedDescription)")
            webView.loadHTMLString(html, baseURL: baseURL)
        }
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
        webView.evaluateJavaScript(script) { _, error in
            guard let error else { return }
            StillmdWebViewLogger.log("evaluateJavaScript failed: \(error.localizedDescription)")
        }
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
        let htmlDocument: TemporaryHTMLDocument?
        private var didReportInitialNavigationCommit = false
        var lastContent: String = ""
        var lastThemePreference: String = ThemePreference.defaultPreference.rawValue
        var lastTextScale: Double = AppPreferences.defaultTextScale
        var lastFindQuery: String = ""
        var lastFindRequestID: Int?
        var lastContainsMermaidFence: Bool = false

        init(_ parent: MarkdownWebView) {
            self.parent = parent
            self.htmlDocument = TemporaryHTMLDocument(rootDirectory: parent.baseURL)
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            reportInitialNavigationIfNeeded()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // `loadFileURL` / `loadHTMLString` では環境によって `didCommit` が期待どおり来ないことがあるためフォールバック。
            reportInitialNavigationIfNeeded()
            runDiagnostics(in: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            StillmdWebViewLogger.log("didFailProvisionalNavigation: \(error.localizedDescription)")
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            StillmdWebViewLogger.log("didFailNavigation: \(error.localizedDescription)")
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            StillmdWebViewLogger.log("web content process terminated")
        }

        private func reportInitialNavigationIfNeeded() {
            guard !didReportInitialNavigationCommit else { return }
            didReportInitialNavigationCommit = true
            let callback = parent.onInitialNavigationCommitted
            DispatchQueue.main.async {
                callback?()
            }
        }

        private func runDiagnostics(in webView: WKWebView) {
            let script = """
            (() => ({
                markedType: typeof marked,
                hljsType: typeof hljs,
                bootPhase: window.__stillmdBootPhase ?? '',
                lastError: window.__stillmdLastError ?? '',
                webkitType: typeof window.webkit,
                scrollHandlerType: typeof window.webkit?.messageHandlers?.scrollPosition,
                contentLength: document.getElementById('content')?.innerHTML?.length ?? -1,
                scrollHeight: document.body?.scrollHeight ?? -1,
                innerWidth: window.innerWidth ?? -1,
                innerHeight: window.innerHeight ?? -1
            }))()
            """

            webView.evaluateJavaScript(script) { [weak self] value, error in
                if let error {
                    StillmdWebViewLogger.logDiagnostic("diagnostic probe failed: \(error.localizedDescription)")
                    return
                }

                guard let info = value as? [String: Any] else { return }
                let contentLength = info["contentLength"] as? Int ?? -1
                let innerHeight = info["innerHeight"] as? Int ?? -1
                if contentLength <= 0 || innerHeight <= 0 {
                    let summary = info
                        .sorted { $0.key < $1.key }
                        .map { "\($0.key)=\($0.value)" }
                        .joined(separator: ", ")
                    let fileName = self?.parent.baseURL.lastPathComponent ?? "unknown"
                    StillmdWebViewLogger.logDiagnostic("suspicious render state for \(fileName): \(summary)")
                }
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

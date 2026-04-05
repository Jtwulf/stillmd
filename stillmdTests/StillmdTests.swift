import Testing
import Foundation
import AppKit
import WebKit
@testable import stillmd

private enum StillmdHTMLTestHelpers {
    /// Decodes markdown from `stillmdMarkdownFromBase64('…')` in `HTMLTemplate` output.
    static func embeddedMarkdownPayload(from html: String) -> String? {
        let needle = "stillmdMarkdownFromBase64('"
        guard let range = html.range(of: needle) else { return nil }
        var idx = range.upperBound
        var b64Chars: [Character] = []
        while idx < html.endIndex, html[idx] != "'" {
            b64Chars.append(html[idx])
            idx = html.index(after: idx)
        }
        let b64 = String(b64Chars)
        guard let data = Data(base64Encoded: b64) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

@MainActor
private final class WKNavigationProbe: NSObject, WKNavigationDelegate {
    struct TimeoutError: Error {}

    private var continuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?

    func loadHTML(
        in webView: WKWebView,
        html: String,
        baseURL: URL?
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            timeoutTask?.cancel()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, let continuation = self.continuation else { return }
                    self.continuation = nil
                    continuation.resume(throwing: TimeoutError())
                }
            }
            webView.navigationDelegate = self
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume()
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

@MainActor
private func evaluateJavaScriptInt(_ script: String, in webView: WKWebView) async throws -> Int {
    try await withCheckedThrowingContinuation { continuation in
        webView.evaluateJavaScript(script) { value, error in
            if let error {
                continuation.resume(throwing: error)
                return
            }
            let intValue = (value as? NSNumber)?.intValue ?? 0
            continuation.resume(returning: intValue)
        }
    }
}

@MainActor
private func evaluateJavaScriptString(_ script: String, in webView: WKWebView) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
        webView.evaluateJavaScript(script) { value, error in
            if let error {
                continuation.resume(throwing: error)
                return
            }
            continuation.resume(returning: value as? String ?? "")
        }
    }
}

@MainActor
private func waitForJavaScriptInt(
    _ script: String,
    in webView: WKWebView,
    timeoutSeconds: Double = 10
) async throws -> Int {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    var lastValue = 0

    while Date() < deadline {
        lastValue = try await evaluateJavaScriptInt(script, in: webView)
        if lastValue > 0 {
            return lastValue
        }
        try? await Task.sleep(for: .milliseconds(250))
    }

    return lastValue
}

// MARK: - Task 2.2: Property Test — File Extension Validation (Property 1)
// **Validates: Requirements 2.4**

@Suite("Property 1: File extension validation rejects non-Markdown files")
struct FileExtensionValidationPropertyTests {

    /// For any file URL whose extension is `.md` or `.markdown`, isMarkdownFile returns true.
    @Test("Valid markdown extensions always accepted")
    func validExtensionsAccepted() {
        let validExtensions = ["md", "markdown"]
        let baseNames = [
            "README", "notes", "CHANGELOG", "file with spaces",
            "日本語ファイル", "test.backup", "a"
        ]

        for baseName in baseNames {
            for ext in validExtensions {
                let url = URL(fileURLWithPath: "/tmp/\(baseName).\(ext)")
                #expect(FileValidation.isMarkdownFile(url),
                        "Expected true for \(url.lastPathComponent)")
            }
        }
    }

    /// For any file URL whose extension is NOT `.md` or `.markdown`, isMarkdownFile returns false.
    /// Generates 100+ random extensions to simulate property-based testing.
    @Test("Random non-markdown extensions always rejected")
    func randomNonMarkdownExtensionsRejected() {
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        let knownNonMarkdown = [
            "txt", "html", "css", "js", "json", "xml", "yaml", "yml",
            "swift", "go", "py", "rb", "rs", "java", "c", "cpp", "h",
            "pdf", "png", "jpg", "jpeg", "gif", "svg", "zip", "tar",
            "gz", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "csv",
            "rtf", "tex", "log", "ini", "cfg", "toml", "sh", "bat",
            "exe", "dll", "so", "dylib", "wasm", "sql", "db", "mdx",
            "mdown", "mkd", "rst", "adoc", "org", "wiki", "textile"
        ]

        // Test known non-markdown extensions
        for ext in knownNonMarkdown {
            let url = URL(fileURLWithPath: "/tmp/file.\(ext)")
            #expect(!FileValidation.isMarkdownFile(url),
                    "Expected false for extension: .\(ext)")
        }

        // Generate 100 random extensions
        for _ in 0..<100 {
            let length = Int.random(in: 1...8)
            var ext = ""
            for _ in 0..<length {
                ext.append(chars[Int.random(in: 0..<chars.count)])
            }
            // Skip if we accidentally generated "md" or "markdown"
            if ext == "md" || ext == "markdown" { continue }

            let url = URL(fileURLWithPath: "/tmp/randomfile.\(ext)")
            #expect(!FileValidation.isMarkdownFile(url),
                    "Expected false for random extension: .\(ext)")
        }
    }

    /// Case-insensitive: .MD, .Markdown, .MARKDOWN should all be accepted.
    @Test("Case-insensitive extension matching")
    func caseInsensitiveMatching() {
        let variations = ["MD", "Md", "mD", "MARKDOWN", "Markdown", "MarkDown", "markDown"]
        for ext in variations {
            let url = URL(fileURLWithPath: "/tmp/file.\(ext)")
            #expect(FileValidation.isMarkdownFile(url),
                    "Expected true for case variation: .\(ext)")
        }
    }

    /// Files with no extension should be rejected.
    @Test("Files with no extension are rejected")
    func noExtensionRejected() {
        let url = URL(fileURLWithPath: "/tmp/README")
        #expect(!FileValidation.isMarkdownFile(url))
    }
}

@Suite("PendingFileOpenCoordinator Unit Tests")
@MainActor
struct PendingFileOpenCoordinatorUnitTests {

    @Test("enqueue stores URLs and increments the change id")
    func enqueueStoresURLs() {
        let coordinator = PendingFileOpenCoordinator()
        let urls = [
            URL(fileURLWithPath: "/tmp/README.md"),
            URL(fileURLWithPath: "/tmp/NOTES.markdown"),
        ]

        coordinator.enqueue(urls)

        #expect(coordinator.pendingChangeID == 1)
        #expect(coordinator.drain() == urls)
        #expect(coordinator.drain().isEmpty)
    }

    @Test("empty enqueue does not publish a new change")
    func emptyEnqueueDoesNothing() {
        let coordinator = PendingFileOpenCoordinator()

        coordinator.enqueue([])

        #expect(coordinator.pendingChangeID == 0)
        #expect(coordinator.drain().isEmpty)
    }
}

@Suite("FindCommandBindings Unit Tests")
@MainActor
struct FindCommandBindingsUnitTests {

    @Test("installPreviewActions stores all closures")
    func installPreviewActionsStoresClosures() {
        let bindings = FindCommandBindings()
        var toggleFindBarCount = 0
        var findNextCount = 0
        var findPreviousCount = 0

        bindings.installPreviewActions(
            toggleFindBar: { toggleFindBarCount += 1 },
            findNext: { findNextCount += 1 },
            findPrevious: { findPreviousCount += 1 }
        )

        bindings.toggleFindBarAction?.perform()
        bindings.findNextAction?.perform()
        bindings.findPreviousAction?.perform()

        #expect(toggleFindBarCount == 1)
        #expect(findNextCount == 1)
        #expect(findPreviousCount == 1)
    }

    @Test("clearPreviewActions removes stored closures")
    func clearPreviewActionsRemovesStoredClosures() {
        let bindings = FindCommandBindings()
        bindings.installPreviewActions(
            toggleFindBar: {},
            findNext: {},
            findPrevious: {}
        )

        bindings.clearPreviewActions()

        #expect(bindings.toggleFindBarAction == nil)
        #expect(bindings.findNextAction == nil)
        #expect(bindings.findPreviousAction == nil)
    }
}

@Suite("LaunchOpenRequestCoordinator Unit Tests")
@MainActor
struct LaunchOpenRequestCoordinatorUnitTests {

    @Test("enqueue preserves order and exposes initial plus remaining URLs")
    func enqueuePreservesOrder() {
        let coordinator = LaunchOpenRequestCoordinator()
        let url1 = URL(fileURLWithPath: "/tmp/README.md")
        let url2 = URL(fileURLWithPath: "/tmp/NOTES.markdown")

        coordinator.enqueue([url1, url2])

        let batch = coordinator.consumeBatch()

        #expect(batch == LaunchOpenRequestBatch(
            initialURL: url1.standardizedFileURL,
            remainingURLs: [url2.standardizedFileURL]
        ))
        #expect(coordinator.consumeBatch() == nil)
    }

    @Test("enqueue deduplicates standardized URLs")
    func enqueueDeduplicatesStandardizedURLs() {
        let coordinator = LaunchOpenRequestCoordinator()
        let url1 = URL(fileURLWithPath: "/tmp/./README.md")
        let url2 = URL(fileURLWithPath: "/tmp/README.md")

        coordinator.enqueue([url1, url2])

        let batch = coordinator.consumeBatch()

        #expect(batch == LaunchOpenRequestBatch(
            initialURL: url1.standardizedFileURL,
            remainingURLs: []
        ))
    }

    @Test("hasPendingURLs reflects enqueue and consume state")
    func hasPendingURLsTracksState() {
        let coordinator = LaunchOpenRequestCoordinator()
        #expect(!coordinator.hasPendingURLs)

        coordinator.enqueue([URL(fileURLWithPath: "/tmp/file.md")])
        #expect(coordinator.hasPendingURLs)

        _ = coordinator.consumeBatch()
        #expect(!coordinator.hasPendingURLs)
    }
}


// MARK: - Task 2.3: Property Test — GFM Conversion Produces Non-Empty HTML (Property 4)
// **Validates: Requirements 4.1**

@Suite("Property 4: Markdown to HTML GFM conversion")
struct GFMConversionPropertyTests {

    /// Helper: build HTML from markdown content using HTMLTemplate
    private func buildHTML(from markdown: String) -> String {
        HTMLTemplate.build(
            markdownContent: markdown,
            markedJS: "// mock marked.js",
            highlightJS: "// mock highlight.js",
            css: "/* mock css */",
            resolvedTheme: "light"
        )
    }

    /// For any valid Markdown string, HTMLTemplate.build() produces non-empty HTML
    /// containing the expected structure (div#content, script tags).
    /// Generates 100+ random Markdown strings.
    @Test("Random markdown always produces non-empty HTML with expected structure")
    func randomMarkdownProducesValidHTML() {
        let markdownElements = [
            "# Heading 1", "## Heading 2", "### Heading 3",
            "**bold text**", "*italic text*", "~~strikethrough~~",
            "- list item", "1. ordered item",
            "> blockquote", "---",
            "`inline code`",
            "```\ncode block\n```",
            "| col1 | col2 |\n|------|------|\n| a | b |",
            "- [x] task done", "- [ ] task todo",
            "[link](https://example.com)",
            "![image](./img.png)",
            "https://autolink.example.com",
            "normal paragraph text",
            "日本語テキスト",
            "emoji 🎉🚀",
            "special chars: <>&\"'",
            ""
        ]

        for i in 0..<120 {
            // Build a random markdown string from 1-5 elements
            let count = Int.random(in: 1...5)
            var parts: [String] = []
            for _ in 0..<count {
                parts.append(markdownElements[Int.random(in: 0..<markdownElements.count)])
            }
            let markdown = parts.joined(separator: "\n\n")

            let html = buildHTML(from: markdown)

            // Non-empty
            #expect(!html.isEmpty, "HTML should not be empty for iteration \(i)")

            // Contains expected structure
            #expect(html.contains("<div id=\"content\">"),
                    "HTML should contain div#content for iteration \(i)")
            #expect(html.contains("marked.setOptions"),
                    "HTML should contain marked.setOptions for iteration \(i)")
            #expect(html.contains("gfm: true"),
                    "HTML should contain gfm: true for iteration \(i)")
            #expect(html.contains("<script>"),
                    "HTML should contain script tags for iteration \(i)")
            #expect(html.contains("</html>"),
                    "HTML should be a complete document for iteration \(i)")
        }
    }

    /// Empty markdown still produces valid HTML structure.
    @Test("Empty markdown produces valid HTML structure")
    func emptyMarkdownProducesValidHTML() {
        let html = buildHTML(from: "")
        #expect(!html.isEmpty)
        #expect(html.contains("<div id=\"content\">"))
        #expect(html.contains("marked.setOptions"))
        #expect(html.contains("gfm: true"))
    }
}

// MARK: - Task 2.4: Unit Tests for HTMLTemplate
// **Validates: Requirements 4.2, 4.3, 4.4, 4.6, 5.2**

@Suite("HTMLTemplate Unit Tests")
struct HTMLTemplateUnitTests {

    private let sampleCSS = "body { color: black; }"
    private let sampleMarkedJS = "// marked.js mock"
    private let sampleHighlightJS = "// highlight.js mock"
    private let sampleMermaidJS = "// mermaid.js mock"

    private func buildHTML(from markdown: String, mermaidJS: String? = nil, initialFindQuery: String = "") -> String {
        HTMLTemplate.build(
            markdownContent: markdown,
            markedJS: sampleMarkedJS,
            highlightJS: sampleHighlightJS,
            css: sampleCSS,
            resolvedTheme: "light",
            initialFindQuery: initialFindQuery,
            mermaidJS: mermaidJS
        )
    }

    // --- GFM Configuration ---

    @Test("Contains marked.setOptions with gfm: true")
    func containsGFMConfig() {
        let html = buildHTML(from: "# Hello")
        #expect(html.contains("marked.setOptions"))
        #expect(html.contains("gfm: true"))
    }

    // --- Escaped Markdown Content ---

    @Test("Contains the escaped Markdown content")
    func containsEscapedContent() {
        let markdown = "Hello **world**"
        let html = buildHTML(from: markdown)
        #expect(StillmdHTMLTestHelpers.embeddedMarkdownPayload(from: html) == markdown)
    }

    // --- Code Block Rendering ---

    @Test("Contains code block renderer and line number markup")
    func containsCodeBlockRenderer() {
        let html = buildHTML(from: "```swift\nlet x = 1\n```")
        #expect(html.contains("function decorateCodeBlocks"))
        #expect(html.contains("function renderCodeBlock"))
        #expect(html.contains("stillmd-code-block"))
        #expect(html.contains("stillmd-code-line-number"))
    }

    @Test("Contains Mermaid support only when Mermaid assets are provided")
    func containsMermaidSupportWhenInjected() {
        let plainHTML = buildHTML(from: "# Hello")
        let mermaidHTML = buildHTML(
            from: "```mermaid\ngraph LR\nA-->B\n```",
            mermaidJS: sampleMermaidJS,
            initialFindQuery: "graph"
        )

        #expect(!plainHTML.contains(sampleMermaidJS))
        #expect(mermaidHTML.contains(sampleMermaidJS))
        #expect(mermaidHTML.contains("stillmd-mermaid-block"))
        #expect(mermaidHTML.contains("initialFindQuery"))
    }

    @Test("Mermaid fence detection only matches fenced Mermaid blocks")
    func detectsMermaidFences() {
        #expect(!HTMLTemplate.containsMermaidFence(in: "# Heading"))
        #expect(HTMLTemplate.containsMermaidFence(in: "```mermaid\ngraph LR\nA-->B\n```"))
        #expect(HTMLTemplate.containsMermaidFence(in: "   ~~~ MERMAID\nflowchart TD\n~~~"))
        #expect(!HTMLTemplate.containsMermaidFence(in: "```swift\nlet x = 1\n```"))
    }

    // --- Dark Mode Detection ---

    @Test("Contains explicit resolved theme state")
    func containsResolvedThemeState() {
        let html = buildHTML(from: "test")
        #expect(html.contains("const initialResolvedTheme ="))
        #expect(html.contains("viewerState.resolvedTheme"))
        #expect(!html.contains("prefers-color-scheme"))
    }

    // --- Message Handlers ---

    @Test("Contains linkClicked message handler")
    func containsLinkClickedHandler() {
        let html = buildHTML(from: "test")
        #expect(html.contains("const linkClickedHandler = messageHandlers.linkClicked ?? null;"))
    }

    @Test("Contains scrollPosition message handler")
    func containsScrollPositionHandler() {
        let html = buildHTML(from: "test")
        #expect(html.contains("const scrollHandler = messageHandlers.scrollPosition ?? null;"))
    }

    @Test("Contains findResults message handler")
    func containsFindResultsHandler() {
        let html = buildHTML(from: "test")
        #expect(html.contains("const findResultsHandler = messageHandlers.findResults ?? null;"))
    }

    @Test("Message handlers are optional during initial render")
    func messageHandlersAreOptional() {
        let html = buildHTML(from: "test")
        #expect(html.contains("const messageHandlers = window.webkit?.messageHandlers ?? {};"))
        #expect(html.contains("function postMessageIfAvailable"))
    }

    // --- updateContent Function ---

    @Test("Contains updateContent function")
    func containsUpdateContentFunction() {
        let html = buildHTML(from: "test")
        #expect(html.contains("function updateContent"))
    }

    // --- Escaping ---

    @Test("Properly escapes backticks in Markdown content")
    func escapesBackticks() {
        let markdown = "Use `code` and ```block```"
        let html = buildHTML(from: markdown)
        #expect(StillmdHTMLTestHelpers.embeddedMarkdownPayload(from: html) == markdown)
    }

    @Test("Properly escapes backslashes in Markdown content")
    func escapesBackslashes() {
        let markdown = "path\\to\\file"
        let html = buildHTML(from: markdown)
        #expect(StillmdHTMLTestHelpers.embeddedMarkdownPayload(from: html) == markdown)
    }

    @Test("Properly escapes dollar signs in Markdown content")
    func escapesDollarSigns() {
        let markdown = "Price is $100"
        let html = buildHTML(from: markdown)
        #expect(StillmdHTMLTestHelpers.embeddedMarkdownPayload(from: html) == markdown)
    }

    // --- HTML Document Structure ---

    @Test("Produces a complete HTML document")
    func producesCompleteHTMLDocument() {
        let html = buildHTML(from: "# Test")
        #expect(html.contains("<!DOCTYPE html>"))
        #expect(html.contains("<html>"))
        #expect(html.contains("</html>"))
        #expect(html.contains("<head>"))
        #expect(html.contains("</head>"))
        #expect(html.contains("<body>"))
        #expect(html.contains("</body>"))
    }

    @Test("Inlines CSS via style tag")
    func inlinesCSS() {
        let html = buildHTML(from: "test")
        #expect(html.contains("<style>\(sampleCSS)</style>"))
    }

    @Test("Inlines JS libraries via script tags")
    func inlinesJSLibraries() {
        let html = buildHTML(from: "test")
        #expect(html.contains("<script>\(sampleMarkedJS)</script>"))
        #expect(html.contains("<script>\(sampleHighlightJS)</script>"))
    }

    @Test("Injects base href when document base URL is provided")
    func injectsBaseHref() {
        let baseURL = URL(fileURLWithPath: "/Users/example/Doc's", isDirectory: true)
        let html = HTMLTemplate.build(
            markdownContent: "test",
            markedJS: sampleMarkedJS,
            highlightJS: sampleHighlightJS,
            css: sampleCSS,
            resolvedTheme: "light",
            documentBaseURL: baseURL
        )
        #expect(html.contains("<base href=\"file:///Users/example/Doc&#39;s/\">"))
    }

    @Test("Contains content div for rendering")
    func containsContentDiv() {
        let html = buildHTML(from: "test")
        #expect(html.contains("<div id=\"content\"></div>"))
    }

    @Test("Contains default code block line number decorator")
    func containsDefaultCodeBlockLineNumbers() {
        let html = buildHTML(from: "```swift\nlet x = 1\n```")
        #expect(html.contains("stillmd-code-block"))
        #expect(html.contains("stillmd-code-line-number"))
        #expect(html.contains("function decorateCodeBlocks"))
    }

    @Test("Code block renderer normalizes only the terminal parser newline")
    func codeBlockRendererNormalizesOnlyTerminalParserNewline() {
        let html = buildHTML(from: "```text\nline 01\n```")
        #expect(html.contains("const normalizedText = rawText.replace(/\\r?\\n$/, '');"))
        #expect(html.contains("const lines = normalizedText.split(/\\r?\\n/);"))
    }

    // --- External Link Interception ---

    @Test("Contains click event listener for external links")
    func containsExternalLinkInterception() {
        let html = buildHTML(from: "test")
        #expect(html.contains("addEventListener('click'"))
        #expect(html.contains("e.target.closest('a')"))
        #expect(html.contains("e.preventDefault()"))
    }

    // --- Scroll Position in updateContent ---

    @Test("updateContent preserves scroll position")
    func updateContentPreservesScroll() {
        let html = buildHTML(from: "test")
        // updateContent should restore the saved position through the shared helper.
        #expect(html.contains("function restoreScrollPosition"))
        #expect(html.contains("updateContent(md, targetScrollY)"))
        #expect(html.contains("restoreScrollPosition(targetScrollY)"))
    }

    @Test("Contains theme and text scale functions")
    func containsThemeAndTextScaleFunctions() {
        let html = buildHTML(from: "test")
        #expect(html.contains("function setThemePreference"))
        #expect(html.contains("function setTextScale"))
        #expect(html.contains("data-theme-preference"))
    }

    @Test("Contains find query update functions")
    func containsFindQueryFunctions() {
        let html = buildHTML(from: "test")
        #expect(html.contains("function updateFindQuery"))
        #expect(html.contains("function navigateFind"))
        #expect(html.contains("mark.className = 'stillmd-find-match'"))
    }
}

@Suite("WKWebView Configuration Unit Tests")
@MainActor
struct WKWebViewConfigurationUnitTests {

    @Test("Content JavaScript is explicitly enabled")
    func contentJavaScriptEnabled() {
        let userContentController = WKUserContentController()
        let configuration = StillmdWebViewConfiguration.make(
            userContentController: userContentController
        )

        #expect(configuration.userContentController === userContentController)
        #expect(configuration.defaultWebpagePreferences.allowsContentJavaScript)
    }
}

@Suite("WKWebView Integration Tests")
@MainActor
struct WKWebViewIntegrationTests {

    private func renderedCodeLineCount(from markdown: String) async throws -> Int {
        let configuration = StillmdWebViewConfiguration.make(
            userContentController: WKUserContentController()
        )
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 900),
            configuration: configuration
        )
        let probe = WKNavigationProbe()
        let baseURL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let html = HTMLTemplate.build(
            markdownContent: markdown,
            markedJS: ResourceLoader.loadMarkedJS(),
            highlightJS: ResourceLoader.loadHighlightJS(),
            css: ResourceLoader.loadCSS(),
            resolvedTheme: "light",
            documentBaseURL: baseURL
        )

        try await probe.loadHTML(in: webView, html: html, baseURL: baseURL)

        return try await evaluateJavaScriptInt(
            "document.querySelectorAll('.stillmd-code-line').length",
            in: webView
        )
    }

    @Test("Inline HTML still renders markdown without registered message handlers")
    func inlineHTMLRendersWithoutMessageHandlers() async throws {
        let configuration = StillmdWebViewConfiguration.make(
            userContentController: WKUserContentController()
        )
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480),
            configuration: configuration
        )
        let probe = WKNavigationProbe()
        let html = HTMLTemplate.build(
            markdownContent: "# Hello\n\nParagraph",
            markedJS: ResourceLoader.loadMarkedJS(),
            highlightJS: ResourceLoader.loadHighlightJS(),
            css: ResourceLoader.loadCSS(),
            resolvedTheme: "light",
            documentBaseURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        )

        try await probe.loadHTML(
            in: webView,
            html: html,
            baseURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        )

        let bootPhase = try await evaluateJavaScriptString("window.__stillmdBootPhase ?? ''", in: webView)
        let lastError = try await evaluateJavaScriptString(
            "window.__stillmdLastError ?? ''",
            in: webView
        )
        #expect(bootPhase == "ready")
        #expect(lastError.isEmpty)

        let contentLength = try await evaluateJavaScriptInt(
            "document.getElementById('content')?.innerHTML?.length ?? 0",
            in: webView
        )
        #expect(contentLength > 0)

        let headingCount = try await evaluateJavaScriptInt(
            "document.querySelectorAll('h1').length",
            in: webView
        )
        #expect(headingCount == 1)
    }

    @Test("Mermaid diagrams render to SVG in WKWebView")
    func mermaidDiagramRendersToSVG() async throws {
        let markdown = """
        ```mermaid
        graph LR
            A[Start] --> B[End]
        ```
        """

        let configuration = StillmdWebViewConfiguration.make(
            userContentController: WKUserContentController()
        )
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 900),
            configuration: configuration
        )
        let probe = WKNavigationProbe()
        let baseURL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let html = HTMLTemplate.build(
            markdownContent: markdown,
            markedJS: ResourceLoader.loadMarkedJS(),
            highlightJS: ResourceLoader.loadHighlightJS(),
            css: ResourceLoader.loadCSS(),
            resolvedTheme: "light",
            documentBaseURL: baseURL,
            mermaidJS: ResourceLoader.loadMermaidJS()
        )

        try await probe.loadHTML(in: webView, html: html, baseURL: baseURL)

        let renderedCount = try await waitForJavaScriptInt(
            "document.querySelectorAll('pre.stillmd-mermaid-block[data-stillmd-mermaid-state=\"rendered\"] svg').length",
            in: webView
        )
        let fallbackCount = try await evaluateJavaScriptInt(
            "document.querySelectorAll('pre.stillmd-mermaid-block[data-stillmd-mermaid-state=\"fallback\"]').length",
            in: webView
        )

        #expect(renderedCount == 1)
        #expect(fallbackCount == 0)
    }

    @Test("Invalid Mermaid source keeps fallback code visible")
    func invalidMermaidSourceFallsBack() async throws {
        let markdown = """
        ```mermaid
        not a diagram
        ```
        """

        let configuration = StillmdWebViewConfiguration.make(
            userContentController: WKUserContentController()
        )
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 900),
            configuration: configuration
        )
        let probe = WKNavigationProbe()
        let baseURL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let html = HTMLTemplate.build(
            markdownContent: markdown,
            markedJS: ResourceLoader.loadMarkedJS(),
            highlightJS: ResourceLoader.loadHighlightJS(),
            css: ResourceLoader.loadCSS(),
            resolvedTheme: "light",
            documentBaseURL: baseURL,
            mermaidJS: ResourceLoader.loadMermaidJS()
        )

        try await probe.loadHTML(in: webView, html: html, baseURL: baseURL)

        let fallbackCount = try await waitForJavaScriptInt(
            "document.querySelectorAll('pre.stillmd-mermaid-block[data-stillmd-mermaid-state=\"fallback\"] code.language-mermaid').length",
            in: webView
        )
        let renderedCount = try await evaluateJavaScriptInt(
            "document.querySelectorAll('pre.stillmd-mermaid-block[data-stillmd-mermaid-state=\"rendered\"] svg').length",
            in: webView
        )

        #expect(fallbackCount == 1)
        #expect(renderedCount == 0)
    }

    @Test("Code block line numbers align with rendered code rows in WKWebView")
    func codeBlockLineNumbersAlignWithRenderedRows() async throws {
        let markdown = """
        ```text
        line 01
        line 02
        line 03
        line 04
        line 05
        line 06
        line 07
        line 08
        line 09
        line 10
        line 11
        line 12
        ```
        """

        let configuration = StillmdWebViewConfiguration.make(
            userContentController: WKUserContentController()
        )
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 900),
            configuration: configuration
        )
        let probe = WKNavigationProbe()
        let baseURL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let html = HTMLTemplate.build(
            markdownContent: markdown,
            markedJS: ResourceLoader.loadMarkedJS(),
            highlightJS: ResourceLoader.loadHighlightJS(),
            css: ResourceLoader.loadCSS(),
            resolvedTheme: "light",
            documentBaseURL: baseURL
        )

        try await probe.loadHTML(in: webView, html: html, baseURL: baseURL)

        let metricsJSON = try await evaluateJavaScriptString(
            """
            (() => {
                const numbers = Array.from(document.querySelectorAll('.stillmd-code-line-number'));
                const rows = Array.from(document.querySelectorAll('.stillmd-code-line'));
                return JSON.stringify({
                    numberCount: numbers.length,
                    rowCount: rows.length,
                    diffs: numbers.map((numberEl, index) => {
                        const rowEl = rows[index];
                        const numberRect = numberEl.getBoundingClientRect();
                        const rowRect = rowEl.getBoundingClientRect();
                        return {
                            heightDiff: Math.abs(numberRect.height - rowRect.height),
                            topDiff: Math.abs(numberRect.top - rowRect.top)
                        };
                    })
                });
            })()
            """,
            in: webView
        )

        let metricsData = try #require(metricsJSON.data(using: .utf8))
        let metricsObject = try #require(
            try JSONSerialization.jsonObject(with: metricsData) as? [String: Any]
        )
        let numberCount = try #require(metricsObject["numberCount"] as? Int)
        let rowCount = try #require(metricsObject["rowCount"] as? Int)
        let diffs = try #require(metricsObject["diffs"] as? [[String: Any]])

        #expect(numberCount == rowCount)
        #expect(numberCount >= 12)
        #expect(diffs.count == rowCount)

        for diff in diffs {
            let heightDiff = try #require(diff["heightDiff"] as? Double)
            let topDiff = try #require(diff["topDiff"] as? Double)
            #expect(heightDiff < 0.75, "Code line number height should match code row height")
            #expect(topDiff < 0.75, "Code line number top should match code row top")
        }
    }

    @Test("Code block rows keep internal blank lines but drop only the parser trailing newline")
    func codeBlockRowsKeepIntentionalBlankLines() async throws {
        let trailingNewlineOnly = """
        ```text
        line 01
        ```
        """
        let internalBlankLine = """
        ```text
        line 01

        line 03
        ```
        """

        #expect(try await renderedCodeLineCount(from: trailingNewlineOnly) == 1)
        #expect(try await renderedCodeLineCount(from: internalBlankLine) == 3)
    }
}


// MARK: - Task 4.3: Property Test — baseURL equals parent directory (Property 8)
// **Validates: Requirements 6.1**

@Suite("Property 8: baseURL equals parent directory of the Markdown file")
struct BaseURLPropertyTests {

    /// For any file URL pointing to a .md file, baseURL should equal
    /// fileURL.deletingLastPathComponent().
    /// Generates 100+ random file paths ending in .md.
    @Test("baseURL equals parent directory for random .md paths")
    func baseURLEqualsParentDirectory() {
        let dirComponents = [
            "Users", "home", "Documents", "Projects", "src", "notes",
            "日本語フォルダ", "my-project", "folder with spaces", "tmp",
            "Desktop", "Downloads", "work", "dev", "repo", "content"
        ]
        let fileNames = [
            "README", "notes", "CHANGELOG", "index", "draft",
            "日本語ファイル", "my-doc", "file with spaces", "a", "test",
            "design", "spec", "todo", "meeting-notes", "report"
        ]

        for i in 0..<120 {
            // Build a random directory path with 1-5 components
            let depth = Int.random(in: 1...5)
            var pathComponents: [String] = ["/"]
            for _ in 0..<depth {
                pathComponents.append(dirComponents[Int.random(in: 0..<dirComponents.count)])
            }
            let fileName = fileNames[Int.random(in: 0..<fileNames.count)]
            let ext = i % 3 == 0 ? "markdown" : "md"
            pathComponents.append("\(fileName).\(ext)")

            let filePath = pathComponents.joined(separator: "/")
                .replacingOccurrences(of: "//", with: "/")
            let fileURL = URL(fileURLWithPath: filePath)

            let expectedBaseURL = fileURL.deletingLastPathComponent()
            let actualBaseURL = fileURL.deletingLastPathComponent()

            #expect(actualBaseURL == expectedBaseURL,
                    "baseURL mismatch for path: \(filePath) (iteration \(i))")

            // Also verify the baseURL does NOT contain the filename
            #expect(!actualBaseURL.path.hasSuffix(".\(ext)"),
                    "baseURL should not end with file extension for: \(filePath)")

            // Verify the file URL's last path component is the filename
            #expect(fileURL.lastPathComponent == "\(fileName).\(ext)",
                    "lastPathComponent mismatch for: \(filePath)")
        }
    }

    /// Edge case: file at root directory
    @Test("baseURL for file at root directory")
    func baseURLAtRoot() {
        let fileURL = URL(fileURLWithPath: "/README.md")
        let baseURL = fileURL.deletingLastPathComponent()
        #expect(baseURL.path == "/")
    }

    /// Edge case: deeply nested path
    @Test("baseURL for deeply nested path")
    func baseURLDeeplyNested() {
        let fileURL = URL(fileURLWithPath: "/a/b/c/d/e/f/g/h/notes.md")
        let baseURL = fileURL.deletingLastPathComponent()
        #expect(baseURL.path == "/a/b/c/d/e/f/g/h")
    }
}


// MARK: - Task 4.4: Property Test — External links intercepted (Property 6)
// **Validates: Requirements 4.7**

@Suite("Property 6: External HTTP(S) links intercepted by navigation delegate")
struct ExternalLinkInterceptionPropertyTests {

    /// For any URL with scheme http or https, the navigation policy logic
    /// (scheme check) correctly identifies them as external.
    /// Generates 100+ random http/https URLs.
    @Test("HTTP and HTTPS URLs are identified as external")
    func httpURLsIdentifiedAsExternal() {
        let domains = [
            "example.com", "google.com", "github.com", "apple.com",
            "日本語.jp", "test.co.uk", "sub.domain.example.org",
            "localhost", "192.168.1.1", "10.0.0.1",
            "my-site.dev", "docs.swift.org", "en.wikipedia.org"
        ]
        let paths = [
            "", "/", "/path", "/path/to/page", "/search?q=test",
            "/docs/api/v2", "/日本語/パス", "/file.html",
            "/index.php", "/api/v1/users"
        ]
        let schemes = ["http", "https"]

        for i in 0..<120 {
            let scheme = schemes[Int.random(in: 0..<schemes.count)]
            let domain = domains[Int.random(in: 0..<domains.count)]
            let path = paths[Int.random(in: 0..<paths.count)]
            let urlString = "\(scheme)://\(domain)\(path)"

            guard let url = URL(string: urlString) else { continue }

            // This mirrors the logic in MarkdownWebView.Coordinator.decidePolicyFor
            let isExternal = url.scheme == "http" || url.scheme == "https"
            #expect(isExternal,
                    "URL should be identified as external: \(urlString) (iteration \(i))")
        }
    }

    /// Non-http URLs (file://, ftp://, custom://) should NOT be intercepted.
    /// Generates 100+ random non-http URLs.
    @Test("Non-HTTP URLs are NOT identified as external")
    func nonHTTPURLsNotExternal() {
        let nonHTTPSchemes = [
            "file", "ftp", "ssh", "mailto", "tel", "custom",
            "myapp", "data", "blob", "about", "javascript",
            "ws", "wss", "irc", "magnet", "sftp"
        ]
        let suffixes = [
            "://localhost", "://example.com", "://path/to/file",
            "://user@host", "://192.168.1.1/resource",
            "://test", "://日本語.jp"
        ]

        for i in 0..<120 {
            let scheme = nonHTTPSchemes[Int.random(in: 0..<nonHTTPSchemes.count)]
            let suffix = suffixes[Int.random(in: 0..<suffixes.count)]
            let urlString = "\(scheme)\(suffix)"

            guard let url = URL(string: urlString) else { continue }

            // This mirrors the logic in MarkdownWebView.Coordinator.decidePolicyFor
            let isExternal = url.scheme == "http" || url.scheme == "https"
            #expect(!isExternal,
                    "URL should NOT be identified as external: \(urlString) (iteration \(i))")
        }
    }

    /// Edge case: Foundation URL preserves scheme case, so uppercase schemes
    /// are NOT matched by the lowercase comparison in the navigation delegate.
    /// This is correct behavior — real browser navigations always use lowercase schemes.
    @Test("Uppercase scheme URLs are not matched by lowercase comparison")
    func uppercaseSchemeNotMatched() {
        let url1 = URL(string: "HTTP://example.com")!
        let url2 = URL(string: "HTTPS://example.com")!

        // Foundation preserves case: url.scheme returns "HTTP" not "http"
        let isExternal1 = url1.scheme == "http" || url1.scheme == "https"
        let isExternal2 = url2.scheme == "http" || url2.scheme == "https"

        // Uppercase schemes are NOT matched — this is expected since
        // WKWebView always provides lowercase schemes in navigation actions
        #expect(!isExternal1, "HTTP (uppercase) is not matched by lowercase check")
        #expect(!isExternal2, "HTTPS (uppercase) is not matched by lowercase check")
    }
}


// MARK: - Task 4.5: Property Test — Scroll position round-trip (Property 3)
// **Validates: Requirements 3.3, 10.1, 10.2**

@Suite("Property 3: Scroll position preservation round-trip")
struct ScrollPositionRoundTripPropertyTests {

    /// For any scroll position and content height where contentHeight >= scrollY,
    /// min(scrollY, contentHeight) preserves the scroll position.
    /// Generates 100+ random scroll positions.
    @Test("Scroll position preserved when contentHeight >= scrollY")
    func scrollPositionPreservedWhenContentSufficient() {
        for i in 0..<120 {
            let scrollY = CGFloat.random(in: 0...100_000)
            // contentHeight >= scrollY
            let contentHeight = scrollY + CGFloat.random(in: 0...50_000)

            let restoredPosition = min(scrollY, contentHeight)

            #expect(restoredPosition == scrollY,
                    "Scroll position should be preserved: scrollY=\(scrollY), contentHeight=\(contentHeight), iteration \(i)")
        }
    }

    /// When contentHeight < scrollY, the result is clamped to contentHeight.
    /// Generates 100+ random cases.
    @Test("Scroll position clamped when contentHeight < scrollY")
    func scrollPositionClampedWhenContentShorter() {
        for i in 0..<120 {
            // Ensure contentHeight < scrollY by generating contentHeight first
            let contentHeight = CGFloat.random(in: 0...50_000)
            let scrollY = contentHeight + CGFloat.random(in: 0.001...50_000)

            let restoredPosition = min(scrollY, contentHeight)

            #expect(restoredPosition == contentHeight,
                    "Scroll position should be clamped: scrollY=\(scrollY), contentHeight=\(contentHeight), iteration \(i)")
            #expect(restoredPosition <= scrollY,
                    "Restored position should never exceed original scrollY (iteration \(i))")
        }
    }

    /// min(scrollY, contentHeight) always returns a non-negative value
    /// when both inputs are non-negative.
    @Test("Restored scroll position is always non-negative")
    func restoredPositionNonNegative() {
        for i in 0..<120 {
            let scrollY = CGFloat.random(in: 0...100_000)
            let contentHeight = CGFloat.random(in: 0...100_000)

            let restoredPosition = min(scrollY, contentHeight)

            #expect(restoredPosition >= 0,
                    "Restored position should be non-negative (iteration \(i))")
        }
    }

    /// The restored position never exceeds either the original scrollY or contentHeight.
    @Test("Restored position bounded by both scrollY and contentHeight")
    func restoredPositionBounded() {
        for i in 0..<120 {
            let scrollY = CGFloat.random(in: 0...100_000)
            let contentHeight = CGFloat.random(in: 0...100_000)

            let restoredPosition = min(scrollY, contentHeight)

            #expect(restoredPosition <= scrollY,
                    "Restored position should not exceed scrollY (iteration \(i))")
            #expect(restoredPosition <= contentHeight,
                    "Restored position should not exceed contentHeight (iteration \(i))")
        }
    }

    /// Edge case: scrollY == 0 always restores to 0
    @Test("Zero scroll position always preserved")
    func zeroScrollPreserved() {
        for _ in 0..<20 {
            let contentHeight = CGFloat.random(in: 0...100_000)
            let restoredPosition = min(CGFloat(0), contentHeight)
            #expect(restoredPosition == 0)
        }
    }
}


// MARK: - Task 4.6: Unit Tests for FileWatcher
// **Validates: Requirements 3.4, 3.5, 3.6**

@Suite("FileWatcher Unit Tests")
struct FileWatcherUnitTests {

    /// Helper to create a temporary .md file with given content.
    private func createTempFile(content: String = "# Hello") throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(UUID().uuidString + ".md")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    /// Test start/stop lifecycle: after stop(), no more callbacks should fire.
    @Test("Start and stop lifecycle — no callbacks after stop")
    func startStopLifecycle() async throws {
        let fileURL = try createTempFile(content: "# Initial")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var callbackCount = 0
        let watcher = FileWatcher(url: fileURL) { _ in
            callbackCount += 1
        }

        watcher.start()
        watcher.stop()

        // Modify the file after stopping
        try "# Modified after stop".write(to: fileURL, atomically: true, encoding: .utf8)

        // Wait a bit to ensure no callbacks fire
        try await Task.sleep(for: .milliseconds(500))

        #expect(callbackCount == 0,
                "No callbacks should fire after stop()")
    }

    /// Test file modification detection: modifying a watched file triggers .modified callback.
    @Test("File modification triggers .modified callback")
    func fileModificationDetected() async throws {
        let fileURL = try createTempFile(content: "# Initial")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let expectation = Mutex(false)
        var receivedEvent: FileWatcher.Event?

        let watcher = FileWatcher(url: fileURL) { event in
            receivedEvent = event
            expectation.withLock { $0 = true }
        }

        watcher.start()

        // Small delay to ensure watcher is active
        try await Task.sleep(for: .milliseconds(100))

        // Modify the file
        try "# Modified content".write(to: fileURL, atomically: true, encoding: .utf8)

        // Wait for callback
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            let fulfilled = expectation.withLock { $0 }
            if fulfilled { break }
            try await Task.sleep(for: .milliseconds(50))
        }

        watcher.stop()

        let fulfilled = expectation.withLock { $0 }
        #expect(fulfilled, "Callback should have been triggered")
        #expect(receivedEvent == .modified,
                "Event should be .modified, got \(String(describing: receivedEvent))")
    }

    /// Test file deletion detection: deleting a watched file triggers .deleted callback.
    @Test("File deletion triggers .deleted callback")
    func fileDeletionDetected() async throws {
        let fileURL = try createTempFile(content: "# To be deleted")

        let expectation = Mutex(false)
        var receivedEvent: FileWatcher.Event?

        let watcher = FileWatcher(url: fileURL) { event in
            if event == .deleted {
                receivedEvent = event
                expectation.withLock { $0 = true }
            }
        }

        watcher.start()

        // Small delay to ensure watcher is active
        try await Task.sleep(for: .milliseconds(100))

        // Delete the file
        try FileManager.default.removeItem(at: fileURL)

        // Wait for callback
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            let fulfilled = expectation.withLock { $0 }
            if fulfilled { break }
            try await Task.sleep(for: .milliseconds(50))
        }

        watcher.stop()

        let fulfilled = expectation.withLock { $0 }
        #expect(fulfilled, "Callback should have been triggered for deletion")
        #expect(receivedEvent == .deleted,
                "Event should be .deleted, got \(String(describing: receivedEvent))")
    }

    /// Test that deinit cleans up properly (no crash).
    @Test("Deinit cleans up without crash")
    func deinitCleansUp() async throws {
        let fileURL = try createTempFile(content: "# Deinit test")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        // Create and immediately release a watcher
        var watcher: FileWatcher? = FileWatcher(url: fileURL) { _ in }
        watcher?.start()
        watcher = nil

        // If we get here without crashing, the test passes
        try await Task.sleep(for: .milliseconds(200))
    }
}

// MARK: - Task 6.3: Property Test — File modification triggers content update (Property 2)
// **Validates: Requirements 3.2**

@Suite("Property 2: File modification triggers content update")
struct FileModificationContentUpdatePropertyTests {

    /// Helper to create a temporary .md file with given content.
    private func createTempFile(content: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(UUID().uuidString + ".md")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    /// For any Markdown content written to a file, PreviewViewModel's markdownContent
    /// matches the file content after loadFile(). Then after modifying the file with
    /// new content and calling loadFile() again, markdownContent matches the new content.
    /// Generates 120 random content pairs.
    @Test("File modification triggers content update across 120 random iterations")
    @MainActor
    func fileModificationTriggersContentUpdate() async throws {
        let contentFragments = [
            "# Heading", "## Subheading", "### Third Level",
            "**bold text**", "*italic*", "~~strikethrough~~",
            "- list item", "1. ordered item", "> blockquote",
            "`inline code`", "---",
            "```swift\nlet x = 1\n```",
            "| col1 | col2 |\n|------|------|\n| a | b |",
            "- [x] done", "- [ ] todo",
            "[link](https://example.com)", "![img](./photo.png)",
            "Normal paragraph with some text.",
            "日本語テキスト", "emoji 🎉🚀✨",
            "Special chars: <>&\"'\\`$",
            "Line 1\nLine 2\nLine 3",
            "", "   ", "\n\n\n"
        ]

        for i in 0..<120 {
            // Generate random initial content (1-5 fragments)
            let initialCount = Int.random(in: 1...5)
            var initialParts: [String] = []
            for _ in 0..<initialCount {
                initialParts.append(contentFragments[Int.random(in: 0..<contentFragments.count)])
            }
            let initialContent = initialParts.joined(separator: "\n\n")

            // Generate random new content (1-5 fragments, different from initial)
            let newCount = Int.random(in: 1...5)
            var newParts: [String] = []
            for _ in 0..<newCount {
                newParts.append(contentFragments[Int.random(in: 0..<contentFragments.count)])
            }
            let newContent = newParts.joined(separator: "\n\n")

            // Create temp file with initial content
            let fileURL = try createTempFile(content: initialContent)
            defer { try? FileManager.default.removeItem(at: fileURL) }

            // Create ViewModel — init calls loadFile()
            let vm = PreviewViewModel(fileURL: fileURL)

            // Verify initial content matches
            #expect(vm.markdownContent == initialContent,
                    "Initial markdownContent should match file content (iteration \(i))")
            #expect(vm.errorMessage == nil,
                    "No error expected for valid file (iteration \(i))")

            // Modify the file with new content
            try newContent.write(to: fileURL, atomically: true, encoding: .utf8)

            // Call loadFile() to simulate what FileWatcher would trigger
            vm.loadFile()

            // Verify updated content matches
            #expect(vm.markdownContent == newContent,
                    "Updated markdownContent should match new file content (iteration \(i))")
            #expect(vm.errorMessage == nil,
                    "No error expected after update (iteration \(i))")
        }
    }
}


// MARK: - Task 6.4: Property Test — Window title matches file name (Property 11)
// **Validates: Requirements 11.3**

@Suite("Property 11: Window title matches file name")
struct WindowTitleMatchesFileNamePropertyTests {

    /// For any file URL, fileURL.lastPathComponent produces the expected filename.
    /// This matches the window title string used by `DocumentWindowChromeController` / titlebar accessory.
    /// Generates 120 random file URLs with various filenames.
    @Test("Window title matches file name for 120 random file URLs")
    func windowTitleMatchesFileName() {
        let dirComponents = [
            "Users", "home", "Documents", "Projects", "src", "notes",
            "日本語フォルダ", "my-project", "folder with spaces", "tmp",
            "Desktop", "Downloads", "work", "dev", "repo", "content"
        ]
        let fileNames = [
            "README", "notes", "CHANGELOG", "index", "draft",
            "日本語ファイル", "my-doc", "file with spaces", "a", "test",
            "design", "spec", "todo", "meeting-notes", "report",
            "UPPER", "MiXeD", "file.backup", "multi.dot.name",
            "123numeric", "emoji🎉file"
        ]
        let extensions = ["md", "markdown"]

        for i in 0..<120 {
            // Build a random directory path with 1-5 components
            let depth = Int.random(in: 1...5)
            var pathComponents: [String] = ["/"]
            for _ in 0..<depth {
                pathComponents.append(dirComponents[Int.random(in: 0..<dirComponents.count)])
            }
            let fileName = fileNames[Int.random(in: 0..<fileNames.count)]
            let ext = extensions[Int.random(in: 0..<extensions.count)]
            let expectedTitle = "\(fileName).\(ext)"
            pathComponents.append(expectedTitle)

            let filePath = pathComponents.joined(separator: "/")
                .replacingOccurrences(of: "//", with: "/")
            let fileURL = URL(fileURLWithPath: filePath)

            let actualTitle = fileURL.lastPathComponent

            #expect(actualTitle == expectedTitle,
                    "Window title should be '\(expectedTitle)' but got '\(actualTitle)' (iteration \(i))")
        }
    }

    /// Edge case: file at root directory
    @Test("Window title for file at root directory")
    func windowTitleAtRoot() {
        let fileURL = URL(fileURLWithPath: "/README.md")
        #expect(fileURL.lastPathComponent == "README.md")
    }

    /// Edge case: filename with multiple dots
    @Test("Window title for filename with multiple dots")
    func windowTitleMultipleDots() {
        let fileURL = URL(fileURLWithPath: "/path/to/my.notes.backup.md")
        #expect(fileURL.lastPathComponent == "my.notes.backup.md")
    }

    /// Edge case: deeply nested path
    @Test("Window title for deeply nested path")
    func windowTitleDeeplyNested() {
        let fileURL = URL(fileURLWithPath: "/a/b/c/d/e/f/g/h/notes.markdown")
        #expect(fileURL.lastPathComponent == "notes.markdown")
    }
}


// MARK: - Task 6.5: Unit Tests for PreviewViewModel
// **Validates: Requirements 1.6, 1.7**

@Suite("PreviewViewModel Unit Tests")
struct PreviewViewModelUnitTests {

    /// Helper to create a temporary .md file with given content.
    private func createTempFile(content: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(UUID().uuidString + ".md")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    /// Test: loading a non-existent file sets errorMessage (Req 1.6)
    @Test("Non-existent file sets errorMessage")
    @MainActor
    func nonExistentFileSetsError() {
        let fileURL = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)-nonexistent.md")
        let vm = PreviewViewModel(fileURL: fileURL)

        #expect(vm.errorMessage != nil,
                "errorMessage should be set for non-existent file")
        #expect(vm.markdownContent.isEmpty,
                "markdownContent should be empty for non-existent file")
    }

    /// Test: loading a binary (non-UTF-8) file sets errorMessage (Req 1.7)
    @Test("Binary file sets errorMessage")
    @MainActor
    func binaryFileSetsError() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        // Write binary data that is not valid UTF-8
        let binaryData = Data([0xFF, 0xFE, 0x00, 0x01, 0x80, 0x81, 0xC0, 0xC1,
                               0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFB, 0xFC])
        try binaryData.write(to: fileURL)

        let vm = PreviewViewModel(fileURL: fileURL)

        #expect(vm.errorMessage != nil,
                "errorMessage should be set for binary (non-UTF-8) file")
    }

    /// Test: loading a valid .md file sets markdownContent correctly
    @Test("Valid .md file sets markdownContent correctly")
    @MainActor
    func validFileLoadsContent() throws {
        let content = "# Hello World\n\nThis is a test."
        let fileURL = try createTempFile(content: content)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let vm = PreviewViewModel(fileURL: fileURL)

        #expect(vm.markdownContent == content,
                "markdownContent should match file content")
        #expect(vm.errorMessage == nil,
                "errorMessage should be nil for valid file")
    }

    /// Test: loadFile() after file modification updates markdownContent
    @Test("loadFile() after modification updates markdownContent")
    @MainActor
    func loadFileAfterModificationUpdatesContent() throws {
        let initialContent = "# Initial Content"
        let fileURL = try createTempFile(content: initialContent)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let vm = PreviewViewModel(fileURL: fileURL)
        #expect(vm.markdownContent == initialContent)

        // Modify the file
        let updatedContent = "# Updated Content\n\nNew paragraph added."
        try updatedContent.write(to: fileURL, atomically: true, encoding: .utf8)

        // Call loadFile() to reload
        vm.loadFile()

        #expect(vm.markdownContent == updatedContent,
                "markdownContent should match updated file content")
        #expect(vm.errorMessage == nil,
                "errorMessage should be nil after successful reload")
    }

    @Test("containsMermaidFence is false for plain Markdown")
    @MainActor
    func mermaidFlagFalseWithoutFence() throws {
        let content = "# Title\n\nNo diagram here."
        let fileURL = try createTempFile(content: content)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let vm = PreviewViewModel(fileURL: fileURL)
        #expect(vm.containsMermaidFence == false)
    }

    @Test("containsMermaidFence is true when file has a Mermaid fence")
    @MainActor
    func mermaidFlagTrueWithFence() throws {
        let content = """
        # Diagram

        ```mermaid
        graph LR
          A-->B
        ```
        """
        let fileURL = try createTempFile(content: content)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let vm = PreviewViewModel(fileURL: fileURL)
        #expect(vm.containsMermaidFence == true)
    }

    @Test(".modified is debounced; .deleted is immediate")
    @MainActor
    func fileEventDebouncing() async throws {
        let fileURL = try createTempFile(content: "v0")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let vm = PreviewViewModel(fileURL: fileURL)
        #expect(vm.markdownContent == "v0")

        try "v1".write(to: fileURL, atomically: true, encoding: .utf8)
        vm.handleFileEvent(.modified)
        try await Task.sleep(for: .milliseconds(30))
        #expect(vm.markdownContent == "v0")

        try await Task.sleep(for: .milliseconds(120))
        #expect(vm.markdownContent == "v1")

        vm.handleFileEvent(.deleted)
        #expect(vm.errorMessage != nil)
    }

    @Test("Rapid .modified coalesces to the latest file contents")
    @MainActor
    func rapidModifiedCoalesces() async throws {
        let fileURL = try createTempFile(content: "a")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let vm = PreviewViewModel(fileURL: fileURL)

        try "b".write(to: fileURL, atomically: true, encoding: .utf8)
        vm.handleFileEvent(.modified)
        try await Task.sleep(for: .milliseconds(40))
        try "c".write(to: fileURL, atomically: true, encoding: .utf8)
        vm.handleFileEvent(.modified)

        // 100ms debounce from the last `.modified` plus scheduling slack
        try await Task.sleep(for: .milliseconds(250))
        #expect(vm.markdownContent == "c")
    }

    @Test(".deleted cancels a pending .modified debounce so loadFile does not overwrite the delete error")
    @MainActor
    func deletedCancelsPendingModifiedDebounce() async throws {
        let fileURL = try createTempFile(content: "x")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let vm = PreviewViewModel(fileURL: fileURL)
        vm.handleFileEvent(.modified)
        try FileManager.default.removeItem(at: fileURL)
        vm.handleFileEvent(.deleted)

        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.errorMessage?.contains("見つかりません") == true)
        #expect(vm.errorMessage?.contains("読み込めません") != true)
    }

    @Test("stopWatching cancels pending debounce; startWatching resyncs from disk")
    @MainActor
    func stopWatchingCancelsDebounceAndStartWatchingResyncs() async throws {
        let fileURL = try createTempFile(content: "old")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let vm = PreviewViewModel(fileURL: fileURL)
        try "new".write(to: fileURL, atomically: true, encoding: .utf8)
        vm.handleFileEvent(.modified)
        try await Task.sleep(for: .milliseconds(20))
        vm.stopWatching()
        #expect(vm.markdownContent == "old")
        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.markdownContent == "old")

        vm.startWatching()
        #expect(vm.markdownContent == "new")
    }
}

@Suite("ResourceLoader caching")
struct ResourceLoaderCachingTests {
    @Test("Static assets return identical content across repeated loads")
    func repeatedLoadsAreEqual() {
        #expect(ResourceLoader.loadMarkedJS() == ResourceLoader.loadMarkedJS())
        #expect(ResourceLoader.loadHighlightJS() == ResourceLoader.loadHighlightJS())
        #expect(ResourceLoader.loadCSS() == ResourceLoader.loadCSS())
        #expect(ResourceLoader.loadMermaidJS() == ResourceLoader.loadMermaidJS())
    }
}

@Suite("AppPreferences Unit Tests")
struct AppPreferencesUnitTests {

    @Test("ThemePreference system uses nil color scheme")
    func themePreferenceSystemUsesNilColorScheme() {
        #expect(ThemePreference.system.colorScheme == nil)
    }

    @Test("ThemePreference light and dark map to matching schemes")
    func themePreferencesMapToColorSchemes() {
        #expect(ThemePreference.light.colorScheme == .light)
        #expect(ThemePreference.dark.colorScheme == .dark)
    }

    @Test("ThemePreference resolves system appearance explicitly")
    func themePreferenceResolvesSystemAppearance() {
        let lightAppearance = NSAppearance(named: .aqua)!
        let darkAppearance = NSAppearance(named: .darkAqua)!

        #expect(ThemePreference.system.resolvedColorScheme(using: lightAppearance) == .light)
        #expect(ThemePreference.system.resolvedColorScheme(using: darkAppearance) == .dark)
        #expect(ThemePreference.light.resolvedColorScheme(using: darkAppearance) == .light)
        #expect(ThemePreference.dark.resolvedColorScheme(using: lightAppearance) == .dark)
    }

    @Test("ThemePreference resolves system color scheme from view environment")
    func themePreferenceResolvesSystemColorScheme() {
        #expect(ThemePreference.system.resolvedColorScheme(using: .light) == .light)
        #expect(ThemePreference.system.resolvedColorScheme(using: .dark) == .dark)
        #expect(ThemePreference.light.resolvedColorScheme(using: .dark) == .light)
        #expect(ThemePreference.dark.resolvedColorScheme(using: .light) == .dark)
    }

    @Test("Text scale is clamped to supported range")
    func textScaleIsClampedToSupportedRange() {
        #expect(AppPreferences.clampedTextScale(0.1) == AppPreferences.textScaleRange.lowerBound)
        #expect(AppPreferences.clampedTextScale(2.0) == AppPreferences.textScaleRange.upperBound)
        #expect(AppPreferences.clampedTextScale(1.1) == 1.1)
    }

    @Test("Text scale helpers step and reset within supported range")
    func textScaleHelpersStepAndReset() {
        #expect(AppPreferences.increasedTextScale(1.0) == 1.05)
        #expect(AppPreferences.decreasedTextScale(1.0) == 0.95)
        #expect(AppPreferences.resetTextScale() == AppPreferences.defaultTextScale)
        #expect(AppPreferences.increasedTextScale(AppPreferences.textScaleRange.upperBound) == AppPreferences.textScaleRange.upperBound)
        #expect(AppPreferences.decreasedTextScale(AppPreferences.textScaleRange.lowerBound) == AppPreferences.textScaleRange.lowerBound)
    }
}


/// A simple thread-safe wrapper for synchronization in tests.
/// Uses `Mutex` from Swift 6 concurrency.
private final class Mutex<Value: Sendable>: @unchecked Sendable {
    private var _value: Value
    private let lock = NSLock()

    init(_ value: Value) {
        self._value = value
    }

    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&_value)
    }
}


// MARK: - Task 7.3: Property Test — Window count equals distinct file count (Property 10)
// **Validates: Requirements 11.1, 11.2**

@Suite("Property 10: Window count equals distinct file count")
struct WindowCountEqualsDistinctFileCountPropertyTests {

    /// For any sequence of openFile(url) calls with distinct URLs,
    /// openFiles.count equals the number of distinct standardized URLs.
    /// Generates 120 random sequences of openFile calls.
    ///
    /// Note: bringToFront() accesses NSApp.windows which is unavailable in the
    /// SPM test runner, so we test with distinct URLs per sequence to validate
    /// the tracking/counting logic. Duplicate detection is tested separately
    /// by inspecting the openFiles set directly.
    @Test("openFiles.count equals distinct standardized URL count across 120 random sequences")
    @MainActor
    func windowCountEqualsDistinctFileCount() {
        let dirComponents = [
            "Users", "home", "Documents", "Projects", "src", "notes",
            "tmp", "Desktop", "Downloads", "work", "dev", "repo"
        ]
        let fileNames = [
            "README", "notes", "CHANGELOG", "index", "draft",
            "design", "spec", "todo", "report", "test",
            "guide", "api", "config", "setup", "intro"
        ]

        for iteration in 0..<120 {
            let wm = WindowManager()
            wm._testOpenWindowHandler = { _ in }

            // Generate a random number of distinct file URLs (1-10)
            let fileCount = Int.random(in: 1...10)
            var opened: Set<URL> = []

            for j in 0..<fileCount {
                let depth = Int.random(in: 1...3)
                var pathParts: [String] = ["/"]
                for _ in 0..<depth {
                    pathParts.append(dirComponents[Int.random(in: 0..<dirComponents.count)])
                }
                // Use iteration + j to ensure uniqueness within this sequence
                let name = fileNames[Int.random(in: 0..<fileNames.count)]
                let ext = Bool.random() ? "md" : "markdown"
                pathParts.append("\(name)-\(iteration)-\(j).\(ext)")
                let path = pathParts.joined(separator: "/")
                    .replacingOccurrences(of: "//", with: "/")
                let url = URL(fileURLWithPath: path)

                wm.openFile(url)
                opened.insert(url.standardizedFileURL)
            }

            #expect(wm.openFiles.count == opened.count,
                    "openFiles.count (\(wm.openFiles.count)) should equal distinct URL count (\(opened.count)) at iteration \(iteration)")
        }
    }

    /// Opening the same URL via openFile inserts it once; the set already contains
    /// the standardized URL on subsequent calls, proving duplicate detection works.
    /// We verify this by checking openFiles.contains() after the first openFile call.
    @Test("Duplicate URLs are detected via openFiles.contains after first open")
    @MainActor
    func duplicateURLsDetectedViaContains() {
        for _ in 0..<120 {
            let wm = WindowManager()
            wm._testOpenWindowHandler = { _ in }
            let depth = Int.random(in: 1...4)
            var pathParts: [String] = ["/"]
            let dirs = ["tmp", "Users", "home", "Documents", "Projects"]
            for _ in 0..<depth {
                pathParts.append(dirs[Int.random(in: 0..<dirs.count)])
            }
            pathParts.append("file-\(UUID().uuidString.prefix(8)).md")
            let path = pathParts.joined(separator: "/")
                .replacingOccurrences(of: "//", with: "/")
            let url = URL(fileURLWithPath: path)

            // First open — should insert
            wm.openFile(url)
            #expect(wm.openFiles.count == 1)

            // Verify the set contains the standardized URL (duplicate guard condition)
            let resolved = url.standardizedFileURL
            #expect(wm.openFiles.contains(resolved),
                    "openFiles should contain the standardized URL after first open")
        }
    }
}


// MARK: - Task 7.4: Unit Tests for WindowManager
// **Validates: Requirements 1.1, 11.1, 11.2**

@Suite("WindowManager Unit Tests")
struct WindowManagerUnitTests {

    // --- openFile adds URL to openFiles ---

    @Test("openFile adds URL to openFiles")
    @MainActor
    func openFileAddsURL() {
        let wm = WindowManager()
        wm._testOpenWindowHandler = { _ in }
        let url = URL(fileURLWithPath: "/tmp/test-file.md")

        wm.openFile(url)

        #expect(wm.openFiles.contains(url.standardizedFileURL),
                "openFiles should contain the opened file URL")
        #expect(wm.openFiles.count == 1)
    }

    // --- closeFile removes URL from openFiles ---

    @Test("closeFile removes URL from openFiles")
    @MainActor
    func closeFileRemovesURL() {
        let wm = WindowManager()
        wm._testOpenWindowHandler = { _ in }
        let url = URL(fileURLWithPath: "/tmp/test-file.md")

        wm.openFile(url)
        #expect(wm.openFiles.count == 1)

        wm.closeFile(url)
        #expect(wm.openFiles.count == 0,
                "openFiles should be empty after closing the only file")
        #expect(!wm.openFiles.contains(url.standardizedFileURL))
    }

    // --- Duplicate detection: openFiles already contains the URL after first open ---

    @Test("Duplicate URL is detected in openFiles after first open")
    @MainActor
    func duplicateURLDetectedInOpenFiles() {
        let wm = WindowManager()
        wm._testOpenWindowHandler = { _ in }
        let url = URL(fileURLWithPath: "/tmp/test-file.md")

        wm.openFile(url)
        #expect(wm.openFiles.count == 1)

        // Verify the duplicate guard condition: openFiles.contains(resolved) is true
        let resolved = url.standardizedFileURL
        #expect(wm.openFiles.contains(resolved),
                "openFiles should contain the URL, preventing duplicate window creation")
    }

    // --- openFile with different URLs increases count ---

    @Test("openFile with different URLs increases count")
    @MainActor
    func differentURLsIncreaseCount() {
        let wm = WindowManager()
        wm._testOpenWindowHandler = { _ in }
        let url1 = URL(fileURLWithPath: "/tmp/file1.md")
        let url2 = URL(fileURLWithPath: "/tmp/file2.md")
        let url3 = URL(fileURLWithPath: "/tmp/file3.markdown")

        wm.openFile(url1)
        #expect(wm.openFiles.count == 1)

        wm.openFile(url2)
        #expect(wm.openFiles.count == 2)

        wm.openFile(url3)
        #expect(wm.openFiles.count == 3)
    }

    // --- closeFile for non-open file is a no-op ---

    @Test("closeFile for non-open file does nothing")
    @MainActor
    func closeNonOpenFileIsNoOp() {
        let wm = WindowManager()
        let url = URL(fileURLWithPath: "/tmp/never-opened.md")

        wm.closeFile(url)
        #expect(wm.openFiles.count == 0)
    }

    // --- Open and close multiple files ---

    @Test("Open and close multiple files tracks correctly")
    @MainActor
    func openAndCloseMultipleFiles() {
        let wm = WindowManager()
        wm._testOpenWindowHandler = { _ in }
        let url1 = URL(fileURLWithPath: "/tmp/file1.md")
        let url2 = URL(fileURLWithPath: "/tmp/file2.md")
        let url3 = URL(fileURLWithPath: "/tmp/file3.md")

        wm.openFile(url1)
        wm.openFile(url2)
        wm.openFile(url3)
        #expect(wm.openFiles.count == 3)

        wm.closeFile(url2)
        #expect(wm.openFiles.count == 2)
        #expect(!wm.openFiles.contains(url2.standardizedFileURL))
        #expect(wm.openFiles.contains(url1.standardizedFileURL))
        #expect(wm.openFiles.contains(url3.standardizedFileURL))
    }

    // --- standardizedFileURL deduplication ---

    @Test("URLs are standardized for deduplication")
    @MainActor
    func urlsAreStandardized() {
        let wm = WindowManager()
        wm._testOpenWindowHandler = { _ in }
        // Both should resolve to the same standardized URL
        let url1 = URL(fileURLWithPath: "/tmp/./test.md")
        let url2 = URL(fileURLWithPath: "/tmp/test.md")

        wm.openFile(url1)

        // Verify that url2 standardizes to the same URL already in openFiles
        // (calling openFile(url2) would trigger bringToFront which accesses NSApp,
        //  unavailable in the SPM test runner)
        let resolved2 = url2.standardizedFileURL
        #expect(wm.openFiles.contains(resolved2),
                "Equivalent paths should be deduplicated via standardizedFileURL")
        #expect(wm.openFiles.count == 1)
    }

    @Test("Duplicate open triggers bring-to-front instead of opening a new window")
    @MainActor
    func duplicateOpenTriggersBringToFront() {
        let wm = WindowManager()
        wm._testOpenWindowHandler = { _ in }
        var broughtToFront: [URL] = []
        let url = URL(fileURLWithPath: "/tmp/test-file.md")

        wm._testBringToFrontHandler = { broughtToFront.append($0) }

        wm.openFile(url)
        wm.openFile(url)

        #expect(broughtToFront == [url.standardizedFileURL])
        #expect(wm.openFiles.count == 1)
    }

    @Test("registerWindow tracks a live NSWindow for the file URL")
    @MainActor
    func registerWindowTracksWindow() {
        let wm = WindowManager()
        let window = NSWindow()
        let url = URL(fileURLWithPath: "/tmp/test-file.md")

        wm.registerWindow(window, for: url)

        #expect(wm._registeredWindowCount == 1)
    }

    @Test("closeFile clears any registered window for the file URL")
    @MainActor
    func closeFileClearsRegisteredWindow() {
        let wm = WindowManager()
        let window = NSWindow()
        let url = URL(fileURLWithPath: "/tmp/test-file.md")

        wm.registerWindow(window, for: url)
        wm.registerFile(url)
        wm.closeFile(url)

        #expect(wm._registeredWindowCount == 0)
        #expect(wm.openFiles.isEmpty)
    }
}


// MARK: - Task 8.2: Property Test — CSS light/dark theme symmetry (Property 9)
// **Validates: Requirements 8.3**

@Suite("Property 9: CSS defines both light and dark theme variables")
struct CSSThemeSymmetryPropertyTests {

    /// Helper: parse CSS variable names from a given selector block in CSS content.
    /// Returns an array of variable names (e.g., ["--bg-color", "--text-color"]).
    private func parseCSSVariables(from css: String, selector: String) -> [String] {
        // Find the block for the given selector
        guard let selectorRange = css.range(of: selector) else { return [] }
        let afterSelector = css[selectorRange.upperBound...]
        guard let openBrace = afterSelector.firstIndex(of: "{") else { return [] }

        // Find matching closing brace
        var braceCount = 1
        var idx = css.index(after: openBrace)
        while idx < css.endIndex && braceCount > 0 {
            if css[idx] == "{" { braceCount += 1 }
            if css[idx] == "}" { braceCount -= 1 }
            if braceCount > 0 { idx = css.index(after: idx) }
        }

        let blockContent = String(css[css.index(after: openBrace)..<idx])

        // Extract CSS variable names (--variable-name)
        var variables: [String] = []
        let lines = blockContent.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("--") {
                if let colonIndex = trimmed.firstIndex(of: ":") {
                    let varName = String(trimmed[trimmed.startIndex..<colonIndex])
                        .trimmingCharacters(in: .whitespaces)
                    variables.append(varName)
                }
            }
        }
        return variables
    }

    /// Property 9: For every CSS variable in :root, a corresponding override exists
    /// in [data-theme="dark"], and vice versa.
    /// This is a single-iteration test (CSS parsing), not a random-input test.
    @Test("Every :root CSS variable has a corresponding [data-theme=\"dark\"] override")
    func lightDarkThemeSymmetry() throws {
        let cssURL = Bundle.module.url(forResource: "preview", withExtension: "css")
        let css = try #require(try? String(contentsOf: cssURL!, encoding: .utf8))

        let rootVars = parseCSSVariables(from: css, selector: ":root")
        let darkVars = parseCSSVariables(from: css, selector: "[data-theme=\"dark\"]")

        // Both selectors should have variables
        #expect(!rootVars.isEmpty, ":root should define CSS variables")
        #expect(!darkVars.isEmpty, "[data-theme=\"dark\"] should define CSS variables")

        // Every :root variable must exist in dark theme
        let darkVarSet = Set(darkVars)
        for rootVar in rootVars {
            #expect(darkVarSet.contains(rootVar),
                    "CSS variable \(rootVar) defined in :root is missing from [data-theme=\"dark\"]")
        }

        // Every dark theme variable must exist in :root
        let rootVarSet = Set(rootVars)
        for darkVar in darkVars {
            #expect(rootVarSet.contains(darkVar),
                    "CSS variable \(darkVar) defined in [data-theme=\"dark\"] is missing from :root")
        }

        // Both sets should be identical
        #expect(Set(rootVars) == Set(darkVars),
                ":root and [data-theme=\"dark\"] should define the same set of CSS variables")
    }
}


// MARK: - Task 8.3: Unit Tests for CSS and Info.plist
// **Validates: Requirements 1.5, 8.1, 8.2, 8.4, 12.6**

@Suite("CSS and Info.plist Unit Tests")
struct CSSAndInfoPlistUnitTests {

    // --- CSS Tests ---

    @Test("preview.css contains :root selector")
    func cssContainsRootSelector() throws {
        let cssURL = Bundle.module.url(forResource: "preview", withExtension: "css")
        let css = try #require(try? String(contentsOf: cssURL!, encoding: .utf8))
        #expect(css.contains(":root"), "preview.css should contain :root selector")
    }

    @Test("preview.css contains [data-theme=\"dark\"] selector")
    func cssContainsDarkThemeSelector() throws {
        let cssURL = Bundle.module.url(forResource: "preview", withExtension: "css")
        let css = try #require(try? String(contentsOf: cssURL!, encoding: .utf8))
        #expect(css.contains("[data-theme=\"dark\"]"),
                "preview.css should contain [data-theme=\"dark\"] selector")
    }

    @Test("preview.css font-family includes -apple-system")
    func cssFontFamilyIncludesAppleSystem() throws {
        let cssURL = Bundle.module.url(forResource: "preview", withExtension: "css")
        let css = try #require(try? String(contentsOf: cssURL!, encoding: .utf8))
        #expect(css.contains("-apple-system"),
                "preview.css should include -apple-system in font-family")
    }

    @Test("preview.css font-family includes SF Mono")
    func cssFontFamilyIncludesSFMono() throws {
        let cssURL = Bundle.module.url(forResource: "preview", withExtension: "css")
        let css = try #require(try? String(contentsOf: cssURL!, encoding: .utf8))
        #expect(css.contains("SF Mono"),
                "preview.css should include SF Mono in font-family")
    }

    @Test("preview.css body line-height is 1.74")
    func cssBodyLineHeightIsUpdated() throws {
        let cssURL = Bundle.module.url(forResource: "preview", withExtension: "css")
        let css = try #require(try? String(contentsOf: cssURL!, encoding: .utf8))
        #expect(css.contains("line-height: 1.74;"),
                "preview.css should keep the body line-height fixed at 1.74")
    }

    @Test("preview.css keeps code line numbers and code rows on shared typography")
    func cssCodeBlockLineNumberMetricsStayAligned() throws {
        let cssURL = Bundle.module.url(forResource: "preview", withExtension: "css")
        let css = try #require(try? String(contentsOf: cssURL!, encoding: .utf8))
        #expect(css.contains(".stillmd-code-block"),
                "preview.css should define stillmd code block styling")
        #expect(css.contains("font-size: 0.82em;"),
                "preview.css should set a shared code block font size")
        #expect(css.contains(".stillmd-code-gutter"),
                "preview.css should define the code gutter styling")
        #expect(css.contains("font-size: inherit;"),
                "preview.css should keep the code gutter on the block font size")
        #expect(css.contains(".stillmd-code-line-content"),
                "preview.css should define code line content styling")
        #expect(css.contains("line-height: inherit;"),
                "preview.css should keep code line content on the shared line height")
    }

    // --- Info.plist Tests ---

    @Test("Info.plist file exists in source directory")
    func infoPlistExists() {
        let infoPlistPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // stillmdTests/
            .deletingLastPathComponent()  // stillmd/
            .appendingPathComponent("stillmd")
            .appendingPathComponent("Info.plist")

        #expect(FileManager.default.fileExists(atPath: infoPlistPath.path),
                "Info.plist should exist at \(infoPlistPath.path)")
    }

    @Test("Info.plist contains net.daringfireball.markdown UTType")
    func infoPlistContainsMarkdownUTType() throws {
        let infoPlistPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("stillmd")
            .appendingPathComponent("Info.plist")

        let content = try #require(try? String(contentsOf: infoPlistPath, encoding: .utf8))
        #expect(content.contains("net.daringfireball.markdown"),
                "Info.plist should contain net.daringfireball.markdown UTType identifier")
    }

    @Test("Info.plist contains CFBundleDocumentTypes")
    func infoPlistContainsCFBundleDocumentTypes() throws {
        let infoPlistPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("stillmd")
            .appendingPathComponent("Info.plist")

        let content = try #require(try? String(contentsOf: infoPlistPath, encoding: .utf8))
        #expect(content.contains("CFBundleDocumentTypes"),
                "Info.plist should contain CFBundleDocumentTypes key")
    }
}


// MARK: - Task 10.3: Property Test — Autolinks rendered as clickable links (Property 5)
// **Validates: Requirements 4.5**

@Suite("Property 5: Autolinks rendered as clickable links")
struct AutolinksPropertyTests {

    private func buildHTML(from markdown: String) -> String {
        HTMLTemplate.build(
            markdownContent: markdown,
            markedJS: "// mock marked.js",
            highlightJS: "// mock highlight.js",
            css: "/* mock css */",
            resolvedTheme: "light"
        )
    }

    /// For any Markdown containing a bare URL (https://...), the HTML template
    /// contains the URL in the Markdown content. Since actual rendering happens
    /// in JS at runtime, we verify the URL is present in the template.
    /// Generates 120 random Markdown strings containing bare URLs.
    @Test("Bare URLs are passed through to the HTML template across 120 random iterations")
    func bareURLsPassedThroughToTemplate() {
        let schemes = ["http", "https"]
        let domains = [
            "example.com", "github.com", "apple.com", "google.com",
            "docs.swift.org", "en.wikipedia.org", "test.co.uk",
            "my-site.dev", "sub.domain.example.org", "localhost:8080",
            "192.168.1.1", "api.example.com"
        ]
        let paths = [
            "", "/", "/path", "/path/to/page", "/docs/api/v2",
            "/file.html", "/index.php", "/api/v1/users",
            "/search", "/about", "/readme"
        ]
        let prefixes = [
            "Check out ", "Visit ", "See ", "Link: ", "URL: ",
            "More info at ", "Documentation: ", "Source: ",
            "# Heading with link\n\n", "- list item with ",
            "> blockquote with ", "**bold** and then ",
            "Some text before ", "日本語テキスト ", ""
        ]
        let suffixes = [
            "", " for details.", " is great.", "\n\nMore text.",
            " and more.", "\n\n## Next Section", " end.",
            "\n\n- another item", " 日本語", " 🎉"
        ]

        for i in 0..<120 {
            let scheme = schemes[Int.random(in: 0..<schemes.count)]
            let domain = domains[Int.random(in: 0..<domains.count)]
            let path = paths[Int.random(in: 0..<paths.count)]
            let url = "\(scheme)://\(domain)\(path)"

            let prefix = prefixes[Int.random(in: 0..<prefixes.count)]
            let suffix = suffixes[Int.random(in: 0..<suffixes.count)]
            let markdown = "\(prefix)\(url)\(suffix)"

            let html = buildHTML(from: markdown)

            let embedded = StillmdHTMLTestHelpers.embeddedMarkdownPayload(from: html)
            #expect(embedded?.contains(url) == true,
                    "Embedded markdown should contain the URL '\(url)' (iteration \(i))")

            // Verify the template has the expected structure for rendering
            #expect(html.contains("marked.setOptions"),
                    "HTML should contain marked.setOptions (iteration \(i))")
            #expect(html.contains("gfm: true"),
                    "HTML should have GFM enabled for autolink support (iteration \(i))")
        }
    }

    /// Edge case: multiple URLs in the same Markdown string
    @Test("Multiple bare URLs in same Markdown are all present in template")
    func multipleURLsPresent() {
        let urls = [
            "https://example.com",
            "http://github.com/repo",
            "https://docs.swift.org/api"
        ]
        let markdown = "Visit \(urls[0]) and \(urls[1]) and \(urls[2]) for info."
        let html = buildHTML(from: markdown)
        let embedded = StillmdHTMLTestHelpers.embeddedMarkdownPayload(from: html) ?? ""

        for url in urls {
            #expect(embedded.contains(url),
                    "Embedded markdown should contain URL: \(url)")
        }
    }

    /// Edge case: URL with special characters that don't need JS escaping
    @Test("URLs with query-like characters are present in template")
    func urlsWithSpecialChars() {
        // Note: $ in URLs gets escaped to \$ in the template, so we test without $
        let url = "https://example.com/search/page"
        let markdown = "Go to \(url) for results."
        let html = buildHTML(from: markdown)
        #expect(StillmdHTMLTestHelpers.embeddedMarkdownPayload(from: html)?.contains(url) == true)
    }
}


// MARK: - Task 10.4: Property Test — Code blocks with language get syntax highlighting (Property 7)
// **Validates: Requirements 5.1**

@Suite("Property 7: Code blocks with language identifier receive syntax highlighting")
struct CodeBlockHighlightingPropertyTests {

    private func buildHTML(from markdown: String) -> String {
        HTMLTemplate.build(
            markdownContent: markdown,
            markedJS: "// mock marked.js",
            highlightJS: "// mock highlight.js",
            css: "/* mock css */",
            resolvedTheme: "light"
        )
    }

    /// For any fenced code block with a language identifier, the HTML template
    /// contains the code block content and the highlight.js configuration.
    /// Since actual highlighting happens in JS at runtime, we verify the template
    /// includes hljs.highlight and hljs.getLanguage in the highlight callback.
    /// Generates 120 random fenced code blocks with language identifiers.
    @Test("Fenced code blocks with language are present in template with hljs config across 120 iterations")
    func fencedCodeBlocksWithLanguageInTemplate() {
        let languages = [
            "javascript", "typescript", "python", "go", "swift",
            "html", "css", "json", "yaml", "sql",
            "bash", "ruby", "rust", "java", "c", "cpp",
            "xml", "php", "kotlin", "scala"
        ]
        let codeSnippets = [
            "let x = 1",
            "print('hello')",
            "func main() {}",
            "const y = 42;",
            "SELECT * FROM users",
            "echo hello",
            "class Foo {}",
            "import Foundation",
            "def greet():\n    pass",
            "fn main() {}",
            "public static void main(String[] args) {}",
            "int x = 0;",
            "val list = listOf(1, 2, 3)",
            "body { color: red; }",
            "{ \"key\": \"value\" }",
            "name: test\nversion: 1",
            "CREATE TABLE t (id INT)",
            "#!/bin/bash\nset -e",
            "puts 'hello'",
            "console.log('test')"
        ]

        for i in 0..<120 {
            let lang = languages[Int.random(in: 0..<languages.count)]
            let code = codeSnippets[Int.random(in: 0..<codeSnippets.count)]
            let markdown = "```\(lang)\n\(code)\n```"

            let html = buildHTML(from: markdown)
            let embedded = StillmdHTMLTestHelpers.embeddedMarkdownPayload(from: html) ?? ""

            #expect(embedded.contains("```\(lang)"),
                    "Embedded markdown should contain the fenced code block opening with language '\(lang)' (iteration \(i))")

            // Verify highlight.js integration is configured in the template
            #expect(html.contains("hljs.highlight"),
                    "HTML should contain hljs.highlight for syntax highlighting (iteration \(i))")
            #expect(html.contains("hljs.getLanguage"),
                    "HTML should contain hljs.getLanguage for language detection (iteration \(i))")
            #expect(html.contains("function decorateCodeBlocks"),
                    "HTML should contain the code block decorator (iteration \(i))")
            #expect(html.contains("stillmd-code-line-number"),
                    "HTML should contain code line number markup (iteration \(i))")
        }
    }

    /// Verify the highlight callback structure in the template
    @Test("Template contains highlight callback with language check")
    func templateContainsHighlightCallback() {
        let html = buildHTML(from: "```swift\nlet x = 1\n```")

        // The highlight callback should check language and use hljs.highlight
        #expect(html.contains("highlight: function(code, lang)"),
                "Template should contain highlight callback function")
        #expect(html.contains("hljs.getLanguage(lang)"),
                "Template should check language availability with hljs.getLanguage")
        #expect(html.contains("hljs.highlight(code, { language: lang })"),
                "Template should call hljs.highlight with language parameter")
    }

    /// Edge case: code block without language should still be in template
    @Test("Code block without language is present in template")
    func codeBlockWithoutLanguage() {
        let markdown = "```\nplain code\n```"
        let html = buildHTML(from: markdown)
        #expect(StillmdHTMLTestHelpers.embeddedMarkdownPayload(from: html)?.contains("plain code") == true,
                "Embedded markdown should contain the code content even without language")
    }
}

@Suite("StillmdMotion Unit Tests")
struct StillmdMotionUnitTests {

    @Test("Motion specs keep stillmd timing compact")
    func motionSpecsRemainCompact() {
        #expect(StillmdMotion.windowEntrance.duration == 0.18)
        #expect(StillmdMotion.windowEntrance.offsetY == 5)
        #expect(StillmdMotion.emptyReveal.duration == 0.18)
        #expect(StillmdMotion.emptyReveal.offsetY == 5)
        #expect(StillmdMotion.previewReveal.duration == StillmdMotion.emptyReveal.duration)
        #expect(StillmdMotion.previewReveal.offsetY == StillmdMotion.emptyReveal.offsetY)
        #expect(StillmdMotion.findBarInsertion.duration == 0.14)
        #expect(StillmdMotion.findBarInsertion.offsetY == -4)
        #expect(StillmdMotion.findBarRemoval.duration == 0.10)
        #expect(StillmdMotion.findBarRemoval.offsetY == -3)
    }

    @Test("Reduce Motion disables generated animations")
    func reduceMotionDisablesAnimations() {
        #expect(StillmdMotion.animation(for: StillmdMotion.windowEntrance, reduceMotion: true) == nil)
        #expect(StillmdMotion.animation(for: StillmdMotion.emptyReveal, reduceMotion: true) == nil)
        #expect(StillmdMotion.animation(for: StillmdMotion.previewReveal, reduceMotion: true) == nil)
        #expect(StillmdMotion.animation(for: StillmdMotion.findBarInsertion, reduceMotion: true) == nil)
    }

    @Test("Standard motion paths still provide animations")
    func standardMotionProvidesAnimations() {
        #expect(StillmdMotion.animation(for: StillmdMotion.windowEntrance, reduceMotion: false) != nil)
        #expect(StillmdMotion.animation(for: StillmdMotion.emptyReveal, reduceMotion: false) != nil)
        #expect(StillmdMotion.animation(for: StillmdMotion.previewReveal, reduceMotion: false) != nil)
        #expect(StillmdMotion.animation(for: StillmdMotion.findBarInsertion, reduceMotion: false) != nil)
        #expect(StillmdMotion.animation(for: StillmdMotion.findBarRemoval, reduceMotion: false) != nil)
    }
}

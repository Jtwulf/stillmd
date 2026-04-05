import Foundation

enum ResourceLoader {
    private static let markedLock = NSLock()
    private static let highlightLock = NSLock()
    private static let mermaidLock = NSLock()
    private static let cssLock = NSLock()

    nonisolated(unsafe) private static var markedCache: String?
    nonisolated(unsafe) private static var highlightCache: String?
    nonisolated(unsafe) private static var mermaidCache: String?
    nonisolated(unsafe) private static var cssCache: String?

    static func loadMarkedJS() -> String {
        markedLock.lock()
        defer { markedLock.unlock() }
        if let markedCache { return markedCache }
        let loaded = loadBundleResource(name: "marked.min", ext: "js")
        markedCache = loaded
        return loaded
    }

    static func loadHighlightJS() -> String {
        highlightLock.lock()
        defer { highlightLock.unlock() }
        if let highlightCache { return highlightCache }
        let loaded = loadBundleResource(name: "highlight.min", ext: "js")
        highlightCache = loaded
        return loaded
    }

    static func loadMermaidJS() -> String {
        mermaidLock.lock()
        defer { mermaidLock.unlock() }
        if let mermaidCache { return mermaidCache }
        let loaded = loadBundleResource(name: "mermaid.min", ext: "js")
        mermaidCache = loaded
        return loaded
    }

    static func loadCSS() -> String {
        cssLock.lock()
        defer { cssLock.unlock() }
        if let cssCache { return cssCache }
        let loaded = loadBundleResource(name: "preview", ext: "css")
        cssCache = loaded
        return loaded
    }

    private static func loadBundleResource(name: String, ext: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("Required resource \(name).\(ext) not found in bundle")
        }
        return content
    }
}

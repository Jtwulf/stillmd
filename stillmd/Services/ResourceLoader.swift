import Foundation

enum ResourceLoader {
    private static let lock = NSLock()
    /// Guarded by `lock` for the whole read-or-load path (no `inout` across lock — see code review).
    nonisolated(unsafe) private static var markedCache: String?
    nonisolated(unsafe) private static var highlightCache: String?
    nonisolated(unsafe) private static var mermaidCache: String?
    nonisolated(unsafe) private static var cssCache: String?

    static func loadMarkedJS() -> String {
        lock.lock()
        defer { lock.unlock() }
        if let markedCache { return markedCache }
        let loaded = loadBundleResource(name: "marked.min", ext: "js")
        markedCache = loaded
        return loaded
    }

    static func loadHighlightJS() -> String {
        lock.lock()
        defer { lock.unlock() }
        if let highlightCache { return highlightCache }
        let loaded = loadBundleResource(name: "highlight.min", ext: "js")
        highlightCache = loaded
        return loaded
    }

    static func loadMermaidJS() -> String {
        lock.lock()
        defer { lock.unlock() }
        if let mermaidCache { return mermaidCache }
        let loaded = loadBundleResource(name: "mermaid.min", ext: "js")
        mermaidCache = loaded
        return loaded
    }

    static func loadCSS() -> String {
        lock.lock()
        defer { lock.unlock() }
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

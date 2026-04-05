import Foundation

enum ResourceLoader {
    private static let lock = NSLock()
    /// Guarded by `lock`; `nonisolated(unsafe)` documents manual synchronization for Swift 6.
    nonisolated(unsafe) private static var markedCache: String?
    nonisolated(unsafe) private static var highlightCache: String?
    nonisolated(unsafe) private static var mermaidCache: String?
    nonisolated(unsafe) private static var cssCache: String?

    static func loadMarkedJS() -> String {
        cached(&markedCache, name: "marked.min", ext: "js")
    }

    static func loadHighlightJS() -> String {
        cached(&highlightCache, name: "highlight.min", ext: "js")
    }

    static func loadMermaidJS() -> String {
        cached(&mermaidCache, name: "mermaid.min", ext: "js")
    }

    static func loadCSS() -> String {
        cached(&cssCache, name: "preview", ext: "css")
    }

    private static func cached(_ slot: inout String?, name: String, ext: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        if let cached = slot {
            return cached
        }
        let loaded = loadBundleResource(name: name, ext: ext)
        slot = loaded
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

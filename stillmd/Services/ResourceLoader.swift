import Foundation

enum ResourceLoader {
    static func loadMarkedJS() -> String {
        loadBundleResource(name: "marked.min", ext: "js")
    }

    static func loadHighlightJS() -> String {
        loadBundleResource(name: "highlight.min", ext: "js")
    }

    static func loadMermaidJS() -> String {
        loadBundleResource(name: "mermaid.min", ext: "js")
    }

    static func loadCSS() -> String {
        loadBundleResource(name: "preview", ext: "css")
    }

    private static func loadBundleResource(name: String, ext: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("Required resource \(name).\(ext) not found in bundle")
        }
        return content
    }
}

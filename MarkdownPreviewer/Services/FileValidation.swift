import Foundation

enum FileValidation {
    /// Returns true only for `.md` and `.markdown` file extensions.
    static func isMarkdownFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }
}

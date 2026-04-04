import AppKit
import Foundation
import UniformTypeIdentifiers

enum FileValidation {
    static let supportedExtensions = ["md", "markdown"]
    static let allowedContentTypes: [UTType] = supportedExtensions.compactMap {
        UTType(filenameExtension: $0)
    }

    /// Returns true only for `.md` and `.markdown` file extensions.
    static func isMarkdownFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }

    @MainActor
    static func configureOpenPanel(_ panel: NSOpenPanel, allowsMultipleSelection: Bool) {
        panel.allowedContentTypes = allowedContentTypes
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.canChooseDirectories = false
    }
}

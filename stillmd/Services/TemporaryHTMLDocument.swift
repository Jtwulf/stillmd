import Foundation

/// Owns a writable HTML file that WKWebView can load via `loadFileURL(_:allowingReadAccessTo:)`.
/// The file lives in its own temporary directory so cleanup can be localized and deterministic.
final class TemporaryHTMLDocument {
    let fileURL: URL

    private let directoryURL: URL
    private let fileManager: FileManager

    init?(
        rootDirectory: URL,
        fileManager: FileManager = .default,
        directoryName: String = ".stillmd-webview-html"
    ) {
        self.fileManager = fileManager

        let stagingDirectory = rootDirectory
            .appendingPathComponent(directoryName, isDirectory: true)
        let uniqueDirectory = stagingDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        do {
            try fileManager.createDirectory(
                at: uniqueDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            return nil
        }

        directoryURL = uniqueDirectory
        fileURL = uniqueDirectory.appendingPathComponent("preview.html", isDirectory: false)
    }

    func write(html: String) throws {
        try html.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    deinit {
        try? fileManager.removeItem(at: directoryURL)

        if let items = try? fileManager.contentsOfDirectory(
            at: directoryURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        ),
        items.isEmpty {
            try? fileManager.removeItem(at: directoryURL.deletingLastPathComponent())
        }
    }
}

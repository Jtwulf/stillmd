import SwiftUI
import UniformTypeIdentifiers

@MainActor
class WindowManager: ObservableObject {
    /// Currently open file URLs (for duplicate detection).
    @Published private(set) var openFiles: Set<URL> = []

    /// Stored reference to the openWindow action, set by the App entry point.
    var openWindowAction: OpenWindowAction?

    func openFile(_ url: URL) {
        let resolved = url.standardizedFileURL
        if openFiles.contains(resolved) {
            bringToFront(resolved)
            return
        }
        openFiles.insert(resolved)
        openWindowAction?(value: resolved)
    }

    func closeFile(_ url: URL) {
        openFiles.remove(url.standardizedFileURL)
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md")!,
            UTType(filenameExtension: "markdown")!,
        ]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            for url in panel.urls {
                openFile(url)
            }
        }
    }

    private func bringToFront(_ url: URL) {
        for window in NSApp.windows {
            // Match by window title (file name) — the title is set to lastPathComponent
            if window.title == url.lastPathComponent {
                window.makeKeyAndOrderFront(nil)
                return
            }
        }
    }
}

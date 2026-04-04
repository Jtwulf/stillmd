import SwiftUI
import UniformTypeIdentifiers

@MainActor
class WindowManager: ObservableObject {
    /// Currently open file URLs (for duplicate detection).
    @Published private(set) var openFiles: Set<URL> = []

    /// Stored reference to the openWindow action, set by the App entry point
    /// via `OpenWindowInjector` before any file can be opened.
    var openWindowAction: OpenWindowAction?

    /// Test-only hook: called instead of `openWindowAction` when set.
    /// Allows unit tests to exercise openFile() without a real SwiftUI environment.
    var _testOpenWindowHandler: ((URL) -> Void)?

    func openFile(_ url: URL) {
        let resolved = url.standardizedFileURL
        if openFiles.contains(resolved) {
            bringToFront(resolved)
            return
        }

        // In tests, use the test handler; in production, use the real action.
        if let testHandler = _testOpenWindowHandler {
            testHandler(resolved)
        } else {
            guard let action = openWindowAction else { return }
            action(value: resolved)
        }
        openFiles.insert(resolved)
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
            // Match by representedURL (full file URL) for accurate identification
            // when multiple files share the same basename.
            if window.representedURL == url {
                window.makeKeyAndOrderFront(nil)
                return
            }
        }
    }
}

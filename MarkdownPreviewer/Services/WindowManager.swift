import SwiftUI
import UniformTypeIdentifiers

@MainActor
class WindowManager: ObservableObject {
    /// Currently open file URLs (for duplicate detection).
    @Published private(set) var openFiles: Set<URL> = []

    /// Stored reference to the active scene's `openWindow` action.
    var openWindowAction: OpenWindowAction?

    /// Test-only hook: called instead of `openWindowAction` when set.
    var _testOpenWindowHandler: ((URL) -> Void)?

    func openFile(_ url: URL) {
        let resolved = url.standardizedFileURL
        if openFiles.contains(resolved) {
            bringToFront(resolved)
            return
        }

        if let testHandler = _testOpenWindowHandler {
            testHandler(resolved)
            openFiles.insert(resolved)
        } else if let action = openWindowAction {
            action(value: resolved)
            openFiles.insert(resolved)
        } else {
            // Cold start fallback: openWindowAction not yet available.
            // Use NSWorkspace to open the file, which triggers handlesExternalEvents
            // and creates a new WindowGroup scene for the URL.
            NSWorkspace.shared.open(url)
        }
    }

    /// Register a file as open (called from PreviewView.onAppear for windows
    /// created externally via Finder, Dock drop, or NSWorkspace fallback).
    func registerFile(_ url: URL) {
        openFiles.insert(url.standardizedFileURL)
    }

    func closeFile(_ url: URL) {
        openFiles.remove(url.standardizedFileURL)
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        FileValidation.configureOpenPanel(panel, allowsMultipleSelection: true)
        if panel.runModal() == .OK {
            for url in panel.urls {
                openFile(url)
            }
        }
    }

    private func bringToFront(_ url: URL) {
        for window in NSApp.windows {
            if window.representedURL == url {
                window.makeKeyAndOrderFront(nil)
                return
            }
        }
    }
}

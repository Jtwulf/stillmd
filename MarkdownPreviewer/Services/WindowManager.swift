import SwiftUI
import UniformTypeIdentifiers

private final class WeakWindowReference {
    weak var window: NSWindow?

    init(window: NSWindow) {
        self.window = window
    }
}

@MainActor
class WindowManager: ObservableObject {
    /// Currently open file URLs (for duplicate detection).
    @Published private(set) var openFiles: Set<URL> = []
    private var windowsByURL: [URL: WeakWindowReference] = [:]

    /// Stored reference to the active scene's `openWindow` action.
    var openWindowAction: OpenWindowAction?

    /// Test-only hook: called instead of `openWindowAction` when set.
    var _testOpenWindowHandler: ((URL) -> Void)?
    var _testBringToFrontHandler: ((URL) -> Void)?
    var _registeredWindowCount: Int {
        pruneWindowReferences()
        return windowsByURL.count
    }

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

    func registerWindow(_ window: NSWindow, for url: URL) {
        pruneWindowReferences()
        windowsByURL[url.standardizedFileURL] = WeakWindowReference(window: window)
    }

    func closeFile(_ url: URL) {
        let resolved = url.standardizedFileURL
        openFiles.remove(resolved)
        windowsByURL.removeValue(forKey: resolved)
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
        if let testHandler = _testBringToFrontHandler {
            testHandler(url)
            return
        }

        pruneWindowReferences()

        if let window = windowsByURL[url]?.window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        for window in NSApp.windows where window.representedURL == url {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
    }

    private func pruneWindowReferences() {
        windowsByURL = windowsByURL.filter { $0.value.window != nil }
    }
}

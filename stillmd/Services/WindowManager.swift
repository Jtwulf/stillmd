import AppKit
import Foundation
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

    /// Opens a new document window for the given file URL (AppKit path via `DocumentWindowFactory`).
    var openNewDocumentHandler: ((URL) -> Void)?

    /// Test-only hook: called instead of `openNewDocumentHandler` when set.
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
        } else if let handler = openNewDocumentHandler {
            handler(resolved)
            openFiles.insert(resolved)
        } else {
            // Cold start fallback before `applicationDidFinishLaunching` wires the handler.
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

        let windowIdentifier = NSUserInterfaceItemIdentifier(url.absoluteString)
        for window in NSApp.windows where window.identifier == windowIdentifier {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
    }

    private func pruneWindowReferences() {
        windowsByURL = windowsByURL.filter { $0.value.window != nil }
    }
}

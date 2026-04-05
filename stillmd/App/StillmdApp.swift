import SwiftUI

enum WindowDefaults {
    // Keep launch size compact without making typical Markdown content feel cramped.
    static let defaultWidth: CGFloat = 720
    static let defaultHeight: CGFloat = 520
    static let minimumWidth: CGFloat = 600
    static let minimumHeight: CGFloat = 400
}

@main
struct StillmdApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var themeState = ThemeState.shared

    private var windowManager: WindowManager {
        appDelegate.windowManager
    }

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(themeState)
                .preferredColorScheme(themeState.themePreference.colorScheme)
        }
        .commands {
            FileCommands(
                windowManager: windowManager,
                pendingCoordinator: appDelegate.pendingFileOpenCoordinator,
                themeState: themeState
            )
            FindCommands()
            TextScaleCommands()
        }
        .restorationBehavior(.disabled)
    }
}

/// Handles Finder "Open With" / file double-click events and document window bootstrap.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let pendingFileOpenCoordinator = PendingFileOpenCoordinator()
    let windowManager = WindowManager()
    let themeState = ThemeState.shared

    private let launchOpenRequestCoordinator = LaunchOpenRequestCoordinator()
    private var livingDocumentWindows: [StillmdDocumentWindow] = []
    private var didFinishLaunching = false

    func trackDocumentWindow(_ window: StillmdDocumentWindow) {
        livingDocumentWindows.append(window)
    }

    func untrackDocumentWindow(_ window: StillmdDocumentWindow) {
        livingDocumentWindows.removeAll { $0 === window }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        windowManager.openNewDocumentHandler = { [weak self] url in
            guard let self else { return }
            DocumentWindowFactory.openDocument(
                initialURL: url,
                windowManager: self.windowManager,
                pendingCoordinator: self.pendingFileOpenCoordinator,
                themeState: self.themeState
            )
        }

        didFinishLaunching = true

        if !openPendingLaunchRequests() {
            DocumentWindowFactory.openDocument(
                windowManager: windowManager,
                pendingCoordinator: pendingFileOpenCoordinator,
                themeState: themeState
            )
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            DocumentWindowFactory.openDocument(
                windowManager: windowManager,
                pendingCoordinator: pendingFileOpenCoordinator,
                themeState: themeState
            )
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let mdURLs = urls.filter { FileValidation.isMarkdownFile($0) }
        guard !mdURLs.isEmpty else { return }

        if !didFinishLaunching {
            launchOpenRequestCoordinator.enqueue(mdURLs)
            return
        }

        pendingFileOpenCoordinator.enqueue(mdURLs)

        // Without a document window, no `RootView` observes `pendingChangeID` to drain the queue.
        let hasDocumentWindow = NSApp.windows.contains { $0 is StillmdDocumentWindow }
        if !hasDocumentWindow {
            DocumentWindowFactory.openDocument(
                windowManager: windowManager,
                pendingCoordinator: pendingFileOpenCoordinator,
                themeState: themeState
            )
        }
    }

    @discardableResult
    private func openPendingLaunchRequests() -> Bool {
        guard let batch = launchOpenRequestCoordinator.consumeBatch() else { return false }

        DocumentWindowFactory.openDocument(
            initialURL: batch.initialURL,
            windowManager: windowManager,
            pendingCoordinator: pendingFileOpenCoordinator,
            themeState: themeState
        )

        for url in batch.remainingURLs {
            windowManager.openFile(url)
        }

        return true
    }
}

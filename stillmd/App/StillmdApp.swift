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
    @AppStorage(AppPreferences.themeKey) private var themePreferenceRawValue =
        ThemePreference.system.rawValue

    private var themePreference: ThemePreference {
        ThemePreference(rawValue: themePreferenceRawValue) ?? .system
    }

    var body: some Scene {
        Settings {
            SettingsView()
                .preferredColorScheme(themePreference.colorScheme)
        }
        .commands {
            FindCommands()
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    appDelegate.windowManager.showOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}

/// Handles Finder "Open With" / file double-click events and document window bootstrap.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let pendingFileOpenCoordinator = PendingFileOpenCoordinator()
    let windowManager = WindowManager()

    private var livingDocumentWindows: [StillmdDocumentWindow] = []

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
                pendingCoordinator: self.pendingFileOpenCoordinator
            )
        }

        DocumentWindowFactory.openDocument(
            windowManager: windowManager,
            pendingCoordinator: pendingFileOpenCoordinator
        )

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            DocumentWindowFactory.openDocument(
                windowManager: windowManager,
                pendingCoordinator: pendingFileOpenCoordinator
            )
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let mdURLs = urls.filter { FileValidation.isMarkdownFile($0) }
        guard !mdURLs.isEmpty else { return }

        pendingFileOpenCoordinator.enqueue(mdURLs)

        // Without a document window, no `RootView` observes `pendingChangeID` to drain the queue.
        let hasDocumentWindow = NSApp.windows.contains { $0 is StillmdDocumentWindow }
        if !hasDocumentWindow {
            DocumentWindowFactory.openDocument(
                windowManager: windowManager,
                pendingCoordinator: pendingFileOpenCoordinator
            )
        }
    }
}

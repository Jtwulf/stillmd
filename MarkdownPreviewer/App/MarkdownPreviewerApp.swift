import SwiftUI

@main
struct MarkdownPreviewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var windowManager = WindowManager()

    var body: some Scene {
        WindowGroup(for: URL.self) { $url in
            RootView(fileURL: $url, windowManager: windowManager)
                .frame(minWidth: 600, minHeight: 400)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    windowManager.showOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
        .defaultSize(width: 860, height: 700)
    }
}

/// NSApplicationDelegate to handle Finder "Open With" and file double-click events.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    /// Pending URLs received before the SwiftUI scene is ready.
    static var pendingURLs: [URL] = []
    /// Reference to openWindow action, set by RootView on appear.
    static var openWindowAction: OpenWindowAction?

    func application(_ application: NSApplication, open urls: [URL]) {
        let mdURLs = urls.filter { FileValidation.isMarkdownFile($0) }
        guard !mdURLs.isEmpty else { return }

        if let action = AppDelegate.openWindowAction {
            for url in mdURLs {
                action(value: url)
            }
        } else {
            // Scene not ready yet — store for later
            AppDelegate.pendingURLs.append(contentsOf: mdURLs)
        }
    }
}

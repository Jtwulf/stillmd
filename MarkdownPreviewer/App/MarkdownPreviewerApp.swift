import SwiftUI

enum WindowDefaults {
    // Keep launch size compact without making typical Markdown content feel cramped.
    static let defaultWidth: CGFloat = 720
    static let defaultHeight: CGFloat = 520
    static let minimumWidth: CGFloat = 600
    static let minimumHeight: CGFloat = 400
}

@main
struct MarkdownPreviewerApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var windowManager = WindowManager()

    var body: some Scene {
        WindowGroup(for: URL.self) { $url in
            RootView(fileURL: $url, windowManager: windowManager)
                .frame(
                    minWidth: WindowDefaults.minimumWidth,
                    minHeight: WindowDefaults.minimumHeight
                )
                .background(
                    LaunchWindowSizer(
                        width: WindowDefaults.defaultWidth,
                        height: WindowDefaults.defaultHeight
                    )
                )
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    windowManager.showOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
        .restorationBehavior(.disabled)
        .defaultSize(
            width: WindowDefaults.defaultWidth,
            height: WindowDefaults.defaultHeight
        )
    }
}

/// Handles Finder "Open With" / file double-click events.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    /// URLs received before the first window's onAppear fires.
    static var pendingURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        let mdURLs = urls.filter { FileValidation.isMarkdownFile($0) }
        guard !mdURLs.isEmpty else { return }
        // Always queue — RootView.onAppear will consume them.
        // This avoids creating a second window via openWindow().
        AppDelegate.pendingURLs.append(contentsOf: mdURLs)
    }
}

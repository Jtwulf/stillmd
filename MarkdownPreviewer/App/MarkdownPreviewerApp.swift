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
    @AppStorage(AppPreferences.themeKey) private var themePreferenceRawValue =
        ThemePreference.system.rawValue

    private var themePreference: ThemePreference {
        ThemePreference(rawValue: themePreferenceRawValue) ?? .system
    }

    var body: some Scene {
        WindowGroup(for: URL.self) { $url in
            RootView(fileURL: $url, windowManager: windowManager)
                .preferredColorScheme(themePreference.colorScheme)
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
            FindCommands()
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

        Settings {
            SettingsView()
                .preferredColorScheme(themePreference.colorScheme)
        }
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

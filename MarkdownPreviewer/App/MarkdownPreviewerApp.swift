import SwiftUI

@main
struct MarkdownPreviewerApp: App {
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

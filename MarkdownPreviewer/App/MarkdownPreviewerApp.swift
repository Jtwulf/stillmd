import SwiftUI

@main
struct MarkdownPreviewerApp: App {
    @StateObject private var windowManager = WindowManager()

    var body: some Scene {
        WindowGroup(for: URL.self) { $url in
            if let url {
                PreviewView(fileURL: url, windowManager: windowManager)
                    .frame(minWidth: 600, minHeight: 400)
            }
        }
        .handlesExternalEvents(matching: ["file"])
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

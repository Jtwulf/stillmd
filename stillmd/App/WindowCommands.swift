import SwiftUI

struct FileCommands: Commands {
    let windowManager: WindowManager
    let pendingCoordinator: PendingFileOpenCoordinator
    let themeState: ThemeState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                DocumentWindowFactory.openDocument(
                    windowManager: windowManager,
                    pendingCoordinator: pendingCoordinator,
                    themeState: themeState
                )
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Open…") {
                windowManager.showOpenPanel()
            }
            .keyboardShortcut("o", modifiers: .command)
        }
    }
}

struct TextScaleCommands: Commands {
    @AppStorage(AppPreferences.textScaleKey) private var textScale = AppPreferences.defaultTextScale

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Divider()

            Button("Zoom In") {
                textScale = AppPreferences.increasedTextScale(textScale)
            }
            .keyboardShortcut("=", modifiers: .command)

            Button("Zoom Out") {
                textScale = AppPreferences.decreasedTextScale(textScale)
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Actual Size") {
                textScale = AppPreferences.resetTextScale()
            }
            .keyboardShortcut("0", modifiers: .command)
        }
    }
}

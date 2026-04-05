import AppKit
import SwiftUI

@MainActor
struct FileCommands: Commands {
    let windowManager: WindowManager
    let pendingCoordinator: PendingFileOpenCoordinator
    let themeState: ThemeState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                let initialFrame = NewWindowCascadePlacement.frame()
                DocumentWindowFactory.openDocument(
                    initialURL: nil,
                    windowManager: windowManager,
                    pendingCoordinator: pendingCoordinator,
                    themeState: themeState,
                    initialFrame: initialFrame
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

@MainActor
enum NewWindowCascadePlacement {
    static func frame() -> NSRect? {
        let referenceWindow = preferredReferenceWindow()
        let visibleFrame = referenceWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        guard let visibleFrame else { return nil }

        let windowSize = NSSize(width: WindowDefaults.defaultWidth, height: WindowDefaults.defaultHeight)
        return WindowPlacementCalculator.cascadedFrame(
            referenceFrame: referenceWindow?.frame,
            visibleFrame: visibleFrame,
            windowSize: windowSize
        )
    }

    @MainActor
    private static func preferredReferenceWindow() -> NSWindow? {
        if let keyWindow = NSApp.keyWindow, keyWindow is StillmdDocumentWindow {
            return keyWindow
        }

        if let mainWindow = NSApp.mainWindow, mainWindow is StillmdDocumentWindow {
            return mainWindow
        }

        return NSApp.windows.first { $0 is StillmdDocumentWindow }
    }
}

@MainActor
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

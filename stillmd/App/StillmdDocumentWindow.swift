import AppKit
import SwiftUI

/// Document window with AppKit-owned chrome (`DocumentWindowChromeController`) and a single `NSHostingView` SwiftUI root.
@MainActor
final class StillmdDocumentWindow: NSWindow, NSWindowDelegate {
    let session: DocumentWindowSession
    let chromeController: DocumentWindowChromeController

    init(
        initialFileURL: URL?,
        windowManager: WindowManager,
        pendingCoordinator: PendingFileOpenCoordinator
    ) {
        let session = DocumentWindowSession(fileURL: initialFileURL)
        self.session = session
        self.chromeController = DocumentWindowChromeController()

        let rect = NSRect(
            x: 0,
            y: 0,
            width: WindowDefaults.defaultWidth,
            height: WindowDefaults.defaultHeight
        )
        super.init(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        delegate = self
        minSize = NSSize(width: WindowDefaults.minimumWidth, height: WindowDefaults.minimumHeight)

        let initialTitle = initialFileURL?.lastPathComponent ?? "stillmd"
        let initialScheme = DocumentWindowChromeBootstrap.initialColorSchemeForNewWindow()

        chromeController.attach(
            window: self,
            windowManager: windowManager,
            initialTitle: initialTitle,
            initialColorScheme: initialScheme,
            initialFileURL: initialFileURL?.standardizedFileURL
        )

        let rootView = RootView(
            documentSession: session,
            windowManager: windowManager,
            pendingFileOpenCoordinator: pendingCoordinator
        )
        .environment(\.documentChromeController, chromeController)

        contentView = NSHostingView(rootView: rootView)
        center()
        makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        chromeController.teardown()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
enum DocumentWindowFactory {
    static func openDocument(
        initialURL: URL? = nil,
        windowManager: WindowManager,
        pendingCoordinator: PendingFileOpenCoordinator
    ) {
        _ = StillmdDocumentWindow(
            initialFileURL: initialURL,
            windowManager: windowManager,
            pendingCoordinator: pendingCoordinator
        )
    }
}

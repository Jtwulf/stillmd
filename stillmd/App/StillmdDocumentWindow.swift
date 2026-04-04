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

        // Swift/ARC: avoid pairing default `true` with a discarded local reference from the factory.
        isReleasedWhenClosed = false

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

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(origin: .zero, size: rect.size)
        hostingView.autoresizingMask = [.width, .height]
        contentView = hostingView
        center()
        makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        chromeController.teardown()
        // `NSWindowDelegate` に `windowDidClose` が無いため、クローズ処理の後に非同期で参照を外す。
        let window = self
        DispatchQueue.main.async {
            (NSApplication.shared.delegate as? AppDelegate)?.untrackDocumentWindow(window)
        }
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
        let window = StillmdDocumentWindow(
            initialFileURL: initialURL,
            windowManager: windowManager,
            pendingCoordinator: pendingCoordinator
        )
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else { return }
        appDelegate.trackDocumentWindow(window)
    }
}

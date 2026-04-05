import AppKit
import SwiftUI

/// Thread-safe via `NSLock`. Marked `@unchecked Sendable` so `DocumentWindowChromeController.deinit` can drop observers safely.
private final class NotificationTokenBag: @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [NSObjectProtocol] = []

    func append(_ token: NSObjectProtocol) {
        lock.lock()
        tokens.append(token)
        lock.unlock()
    }

    func removeAll() {
        lock.lock()
        let snapshot = tokens
        tokens.removeAll()
        lock.unlock()
        for token in snapshot {
            NotificationCenter.default.removeObserver(token)
        }
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return tokens.isEmpty
    }
}

/// Owns document-window chrome for a single `NSWindow`: structural settings and lifecycle reapply.
/// Invoked from `StillmdDocumentWindow` and `RootView` state changes — not from SwiftUI `updateNSView` churn.
@MainActor
final class DocumentWindowChromeController: NSObject {
    private weak var window: NSWindow?
    private weak var observedWindow: NSWindow?
    private let notificationObservers = NotificationTokenBag()
    private var lifecycleReapply: (() -> Void)?
    private var geometryReapplyWorkItem: DispatchWorkItem?

    private var latestTitle = ""
    private var latestColorScheme = ColorScheme.light
    private var latestFileURL: URL?
    private weak var latestWindowManager: WindowManager?

    deinit {
        notificationObservers.removeAll()
    }

    func attach(
        window: NSWindow,
        windowManager: WindowManager,
        initialTitle: String,
        initialColorScheme: ColorScheme,
        initialFileURL: URL?
    ) {
        self.window = window
        latestWindowManager = windowManager
        latestTitle = initialTitle
        latestColorScheme = initialColorScheme
        latestFileURL = initialFileURL

        applyConfiguration(to: window)
        startWindowLifecycleObserversIfNeeded(for: window)
    }

    func teardown() {
        cancelGeometryReapplyWorkItem()
        removeWindowLifecycleObservers()
        window = nil
    }

    /// Call when SwiftUI-driven title / theme / file binding changes.
    func syncFromSwiftUI(
        title: String,
        colorScheme: ColorScheme,
        fileURL: URL?,
        windowManager: WindowManager
    ) {
        latestTitle = title
        latestColorScheme = colorScheme
        latestFileURL = fileURL
        latestWindowManager = windowManager
        guard let window else { return }
        applyConfiguration(to: window)
    }

    private func applyConfiguration(to window: NSWindow) {
        window.title = latestTitle
        if let fileURL = latestFileURL {
            window.representedURL = fileURL
        } else {
            window.representedURL = nil
        }
        window.representedFilename = ""
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.backgroundColor = WindowSurfacePalette.nsBackground(for: latestColorScheme)

        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
        }

        window.standardWindowButton(.documentIconButton)?.isHidden = true
        window.standardWindowButton(.documentIconButton)?.alphaValue = 0
        window.standardWindowButton(.documentVersionsButton)?.isHidden = true

        if let fileURL = latestFileURL {
            window.identifier = NSUserInterfaceItemIdentifier(fileURL.absoluteString)
            latestWindowManager?.registerWindow(window, for: fileURL)
        } else {
            window.identifier = NSUserInterfaceItemIdentifier("stillmd.window")
        }
    }

    private func startWindowLifecycleObserversIfNeeded(for window: NSWindow) {
        if observedWindow === window, !notificationObservers.isEmpty {
            return
        }

        removeWindowLifecycleObservers()
        observedWindow = window

        let center = NotificationCenter.default
        let immediateNames: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didResignMainNotification,
            NSWindow.didChangeScreenNotification,
            NSWindow.didChangeBackingPropertiesNotification,
        ]

        for name in immediateNames {
            let token = center.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.lifecycleReapply?()
                }
            }
            notificationObservers.append(token)
        }

        let moveToken = center.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.scheduleDebouncedGeometryReapply()
            }
        }
        notificationObservers.append(moveToken)

        lifecycleReapply = { [weak self] in
            guard let self, let win = self.window else { return }
            self.applyConfiguration(to: win)
        }
    }

    private func scheduleDebouncedGeometryReapply() {
        geometryReapplyWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            geometryReapplyWorkItem = nil
            lifecycleReapply?()
        }
        geometryReapplyWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    private func cancelGeometryReapplyWorkItem() {
        geometryReapplyWorkItem?.cancel()
        geometryReapplyWorkItem = nil
    }

    private func removeWindowLifecycleObservers() {
        cancelGeometryReapplyWorkItem()
        notificationObservers.removeAll()
        observedWindow = nil
        lifecycleReapply = nil
    }

}

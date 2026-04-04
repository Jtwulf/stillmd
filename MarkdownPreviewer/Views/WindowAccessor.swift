import AppKit
import SwiftUI

private final class NotificationTokenBag: @unchecked Sendable {
    private var tokens: [NSObjectProtocol] = []

    func append(_ token: NSObjectProtocol) {
        tokens.append(token)
    }

    func removeAll() {
        let snapshot = tokens
        tokens.removeAll()
        for token in snapshot {
            NotificationCenter.default.removeObserver(token)
        }
    }

    var isEmpty: Bool {
        tokens.isEmpty
    }
}

private struct TitlebarDocumentTitleView: View {
    let title: String
    let colorScheme: ColorScheme

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .background(WindowSurfacePalette.background(for: colorScheme))
    }
}

@MainActor
private final class StillmdDocumentTitleAccessoryController: NSTitlebarAccessoryViewController {
    private let hostingView: NSHostingView<TitlebarDocumentTitleView>

    init(title: String, colorScheme: ColorScheme) {
        let root = TitlebarDocumentTitleView(title: title, colorScheme: colorScheme)
        self.hostingView = NSHostingView(rootView: root)
        super.init(nibName: nil, bundle: nil)
        self.view = hostingView
        // `.leading` places the accessory on the titlebar row beside the traffic lights.
        // `.bottom` would render below the titlebar, which breaks the unified chrome row.
        layoutAttribute = .leading
        fullScreenMinHeight = 28
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateContent(title: String, colorScheme: ColorScheme) {
        hostingView.rootView = TitlebarDocumentTitleView(title: title, colorScheme: colorScheme)
        hostingView.invalidateIntrinsicContentSize()
    }
}

/// An invisible `NSViewRepresentable` that configures the hosting `NSWindow`
/// and registers it with `WindowManager`.
@MainActor
struct WindowAccessor: NSViewRepresentable {
    let fileURL: URL?
    let title: String
    let colorScheme: ColorScheme
    @ObservedObject var windowManager: WindowManager

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.hostView = view
        Task { @MainActor in
            updateWindow(from: view, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hostView = nsView
        Task { @MainActor in
            updateWindow(from: nsView, coordinator: context.coordinator)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    private func updateWindow(from view: NSView, coordinator: Coordinator) {
        guard let window = view.window else { return }
        coordinator.configurationSequence += 1
        let sequence = coordinator.configurationSequence

        coordinator.latestTitle = title
        coordinator.latestColorScheme = colorScheme
        coordinator.latestFileURL = fileURL
        coordinator.latestWindowManager = windowManager

        coordinator.startWindowLifecycleObserversIfNeeded(for: window) { [weak coordinator] in
            guard let coordinator else { return }
            guard let host = coordinator.hostView, let win = host.window else { return }
            guard let windowManager = coordinator.latestWindowManager else { return }
            Self.applyConfiguration(
                to: win,
                title: coordinator.latestTitle,
                colorScheme: coordinator.latestColorScheme,
                fileURL: coordinator.latestFileURL,
                windowManager: windowManager,
                coordinator: coordinator
            )
        }

        Self.applyConfiguration(
            to: window,
            title: title,
            colorScheme: colorScheme,
            fileURL: fileURL,
            windowManager: windowManager,
            coordinator: coordinator
        )

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard coordinator.configurationSequence == sequence else { return }
            guard let host = coordinator.hostView, let win = host.window else { return }
            guard let windowManager = coordinator.latestWindowManager else { return }
            Self.applyConfiguration(
                to: win,
                title: coordinator.latestTitle,
                colorScheme: coordinator.latestColorScheme,
                fileURL: coordinator.latestFileURL,
                windowManager: windowManager,
                coordinator: coordinator
            )
        }
    }

    private static func applyConfiguration(
        to window: NSWindow,
        title: String,
        colorScheme: ColorScheme,
        fileURL: URL?,
        windowManager: WindowManager,
        coordinator: Coordinator
    ) {
        window.title = title
        window.representedURL = nil
        window.representedFilename = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.backgroundColor = WindowSurfacePalette.nsBackground(for: colorScheme)

        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
        }

        window.standardWindowButton(.documentIconButton)?.isHidden = true
        window.standardWindowButton(.documentIconButton)?.alphaValue = 0
        window.standardWindowButton(.documentVersionsButton)?.isHidden = true

        if let fileURL {
            window.identifier = NSUserInterfaceItemIdentifier(fileURL.absoluteString)
            windowManager.registerWindow(window, for: fileURL)
        } else {
            window.identifier = NSUserInterfaceItemIdentifier("stillmd.window")
        }

        coordinator.syncDocumentTitleAccessory(on: window, title: title, colorScheme: colorScheme)
    }

    @MainActor
    final class Coordinator {
        var configurationSequence = 0
        weak var hostView: NSView?

        var latestTitle = ""
        var latestColorScheme = ColorScheme.light
        var latestFileURL: URL?
        weak var latestWindowManager: WindowManager?

        private weak var observedWindow: NSWindow?
        private let notificationObservers = NotificationTokenBag()
        private var lifecycleReapply: (() -> Void)?
        private var documentTitleAccessory: StillmdDocumentTitleAccessoryController?
        private weak var accessoryWindow: NSWindow?

        deinit {
            notificationObservers.removeAll()
        }

        func teardown() {
            // Invalidate any in-flight delayed reapply work from `updateWindow`.
            configurationSequence += 1
            removeWindowLifecycleObservers()
            if let accessory = documentTitleAccessory, let window = accessoryWindow,
                let index = window.titlebarAccessoryViewControllers.firstIndex(where: { $0 === accessory })
            {
                window.removeTitlebarAccessoryViewController(at: index)
            }
            documentTitleAccessory = nil
            accessoryWindow = nil
        }

        func startWindowLifecycleObserversIfNeeded(for window: NSWindow, reapply: @escaping () -> Void) {
            if observedWindow === window, !notificationObservers.isEmpty {
                lifecycleReapply = reapply
                return
            }

            removeWindowLifecycleObservers()
            observedWindow = window
            lifecycleReapply = reapply

            let center = NotificationCenter.default
            let names: [Notification.Name] = [
                NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification,
                NSWindow.didBecomeMainNotification,
                NSWindow.didResignMainNotification,
            ]

            for name in names {
                let token = center.addObserver(
                    forName: name,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.lifecycleReapply?()
                    }
                }
                notificationObservers.append(token)
            }
        }

        private func removeWindowLifecycleObservers() {
            notificationObservers.removeAll()
            observedWindow = nil
            lifecycleReapply = nil
        }

        func syncDocumentTitleAccessory(on window: NSWindow, title: String, colorScheme: ColorScheme) {
            if let accessory = documentTitleAccessory {
                let attachedToCurrent = window.titlebarAccessoryViewControllers.contains(where: { $0 === accessory })
                if !attachedToCurrent {
                    if let previous = accessoryWindow,
                        let index = previous.titlebarAccessoryViewControllers.firstIndex(where: { $0 === accessory })
                    {
                        previous.removeTitlebarAccessoryViewController(at: index)
                    }
                    documentTitleAccessory = nil
                    accessoryWindow = nil
                }
            }

            if let accessory = documentTitleAccessory {
                accessory.updateContent(title: title, colorScheme: colorScheme)
                accessoryWindow = window
                return
            }

            let accessory = StillmdDocumentTitleAccessoryController(title: title, colorScheme: colorScheme)
            documentTitleAccessory = accessory
            accessoryWindow = window
            window.addTitlebarAccessoryViewController(accessory)
        }
    }
}

import SwiftUI

/// An invisible `NSViewRepresentable` that configures the hosting `NSWindow`
/// and registers it with `WindowManager`.
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
        DispatchQueue.main.async {
            updateWindow(from: view, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            updateWindow(from: nsView, coordinator: context.coordinator)
        }
    }

    private func updateWindow(from view: NSView, coordinator: Coordinator) {
        guard let window = view.window else { return }
        coordinator.configurationSequence += 1
        let sequence = coordinator.configurationSequence

        applyConfiguration(to: window)

        // SwiftUI may re-assert document metadata after the first pass.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard coordinator.configurationSequence == sequence else { return }
            applyConfiguration(to: window)
        }
    }

    private func applyConfiguration(to window: NSWindow) {
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
    }

    final class Coordinator {
        var configurationSequence = 0
    }
}

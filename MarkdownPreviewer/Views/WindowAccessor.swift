import SwiftUI

/// An invisible `NSViewRepresentable` that configures the hosting `NSWindow`
/// and registers it with `WindowManager`.
struct WindowAccessor: NSViewRepresentable {
    let fileURL: URL?
    let title: String
    let colorScheme: ColorScheme
    @ObservedObject var windowManager: WindowManager

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            updateWindow(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            updateWindow(from: nsView)
        }
    }

    private func updateWindow(from view: NSView) {
        guard let window = view.window else { return }

        applyConfiguration(to: window)

        // SwiftUI may re-assert document metadata after the first pass.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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
            windowManager.registerWindow(window, for: fileURL)
        }
    }
}

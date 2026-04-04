import SwiftUI

/// An invisible `NSViewRepresentable` that sets `representedURL` on its own
/// hosting `NSWindow`. This avoids the unreliable `NSApp.windows.first(where:)`
/// lookup which can target the wrong window in multi-window scenarios.
struct WindowAccessor: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.representedURL = url
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.representedURL = url
        }
    }
}

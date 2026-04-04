import AppKit
import SwiftUI

struct LaunchWindowSizer: NSViewRepresentable {
    let width: CGFloat
    let height: CGFloat

    func makeNSView(context: Context) -> SizingView {
        let view = SizingView()
        view.desiredSize = NSSize(width: width, height: height)
        return view
    }

    func updateNSView(_ nsView: SizingView, context: Context) {
        nsView.desiredSize = NSSize(width: width, height: height)
        nsView.applyIfNeeded()
    }
}

final class SizingView: NSView {
    var desiredSize: NSSize = .zero
    private var didApply = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyIfNeeded()
    }

    func applyIfNeeded() {
        guard !didApply, let window, desiredSize != .zero else { return }

        window.setContentSize(desiredSize)
        didApply = true
    }
}

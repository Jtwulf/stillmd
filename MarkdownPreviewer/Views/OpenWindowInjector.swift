import SwiftUI

/// A transparent wrapper view that captures the `@Environment(\.openWindow)` action
/// and injects it into `WindowManager` on first appear. This ensures `openWindowAction`
/// is set before any in-app file open can be triggered.
struct OpenWindowInjector<Content: View>: View {
    @ObservedObject var windowManager: WindowManager
    @Environment(\.openWindow) private var openWindow
    let content: Content

    init(windowManager: WindowManager, @ViewBuilder content: () -> Content) {
        self.windowManager = windowManager
        self.content = content()
    }

    var body: some View {
        content
            .onAppear {
                windowManager.openWindowAction = openWindow
            }
    }
}

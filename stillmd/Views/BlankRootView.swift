import SwiftUI

struct BlankRootView: View {
    @State private var fileURL: URL? = nil
    @ObservedObject var windowManager: WindowManager
    @ObservedObject var pendingFileOpenCoordinator: PendingFileOpenCoordinator

    var body: some View {
        RootView(
            fileURL: $fileURL,
            windowManager: windowManager,
            pendingFileOpenCoordinator: pendingFileOpenCoordinator
        )
    }
}

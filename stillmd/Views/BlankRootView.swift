import SwiftUI

struct BlankRootView: View {
    @StateObject private var documentSession = DocumentWindowSession()
    @ObservedObject var windowManager: WindowManager
    @ObservedObject var pendingFileOpenCoordinator: PendingFileOpenCoordinator

    var body: some View {
        RootView(
            documentSession: documentSession,
            windowManager: windowManager,
            pendingFileOpenCoordinator: pendingFileOpenCoordinator
        )
    }
}

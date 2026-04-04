import SwiftUI

struct RootView: View {
    @Binding var fileURL: URL?
    @ObservedObject var windowManager: WindowManager
    @ObservedObject var pendingFileOpenCoordinator: PendingFileOpenCoordinator
    @Environment(\.openWindow) private var openWindow

    @State private var isReady = false
    @State private var isDropTargeted = false

    var body: some View {
        Group {
            if let url = fileURL {
                PreviewView(fileURL: url, windowManager: windowManager)
            } else {
                EmptyStateView(
                    onOpen: {
                        openFileInCurrentWindow()
                    },
                    isDropTargeted: isDropTargeted
                )
            }
        }
        .opacity(isReady ? 1 : 0)
        .animation(.easeOut(duration: 0.16), value: isReady)
        .onAppear {
            windowManager.openWindowAction = openWindow

            if fileURL != nil {
                isReady = true
                return
            }

            if consumePendingURLs() {
                isReady = true
                return
            }

            revealEmptyStateIfNeeded()
        }
        .onChange(of: pendingFileOpenCoordinator.pendingChangeID) { _, _ in
            if consumePendingURLs(), !isReady {
                isReady = true
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .navigationTitle(fileURL?.lastPathComponent ?? "stillmd")
    }

    private func revealEmptyStateIfNeeded() {
        Task { @MainActor in
            await Task.yield()

            if consumePendingURLs() {
                isReady = true
                return
            }

            if !isReady {
                withAnimation(.easeOut(duration: 0.16)) {
                    isReady = true
                }
            }
        }
    }

    @discardableResult
    private func consumePendingURLs() -> Bool {
        let pendingURLs = pendingFileOpenCoordinator.drain()
        guard !pendingURLs.isEmpty else { return false }

        var remainingURLs = pendingURLs
        if fileURL == nil, let initialURL = remainingURLs.first {
            fileURL = initialURL
            remainingURLs.removeFirst()
        }

        for url in remainingURLs {
            windowManager.openFile(url)
        }

        return true
    }

    private func openFileInCurrentWindow() {
        let panel = NSOpenPanel()
        FileValidation.configureOpenPanel(panel, allowsMultipleSelection: false)
        if panel.runModal() == .OK, let url = panel.url {
            fileURL = url
            if !isReady {
                isReady = true
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, FileValidation.isMarkdownFile(url) else { return }
                Task { @MainActor in
                    if self.fileURL == nil {
                        self.fileURL = url
                    } else {
                        self.windowManager.openFile(url)
                    }
                }
            }
        }
        return true
    }
}

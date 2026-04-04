import SwiftUI
import UniformTypeIdentifiers

struct PreviewView: View {
    let fileURL: URL
    @ObservedObject var windowManager: WindowManager
    @StateObject private var viewModel: PreviewViewModel
    @Environment(\.openWindow) private var openWindow

    init(fileURL: URL, windowManager: WindowManager) {
        self.fileURL = fileURL
        self.windowManager = windowManager
        _viewModel = StateObject(wrappedValue: PreviewViewModel(fileURL: fileURL))
    }

    var body: some View {
        Group {
            if let error = viewModel.errorMessage {
                ErrorView(message: error)
            } else {
                MarkdownWebView(
                    markdownContent: viewModel.markdownContent,
                    baseURL: fileURL.deletingLastPathComponent(),
                    scrollPosition: $viewModel.scrollPosition
                )
            }
        }
        .navigationTitle(fileURL.lastPathComponent)
        .onAppear {
            windowManager.openWindowAction = openWindow
            viewModel.startWatching()
        }
        .onDisappear {
            viewModel.stopWatching()
            windowManager.closeFile(fileURL)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let hasFileURL = providers.contains { $0.canLoadObject(ofClass: URL.self) }
        guard hasFileURL else { return false }

        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, FileValidation.isMarkdownFile(url) else { return }
                Task { @MainActor in
                    windowManager.openFile(url)
                }
            }
        }
        return true
    }
}

import SwiftUI
import UniformTypeIdentifiers

/// Root view that handles both the empty state (no file) and the preview state.
struct RootView: View {
    @Binding var fileURL: URL?
    @ObservedObject var windowManager: WindowManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let url = fileURL {
                PreviewView(fileURL: url, windowManager: windowManager)
            } else {
                EmptyStateView {
                    openFileInCurrentWindow()
                }
            }
        }
        .onAppear {
            windowManager.openWindowAction = openWindow
            AppDelegate.openWindowAction = openWindow

            // Process any URLs that arrived before the scene was ready
            // (e.g., Finder "Open With" on cold start)
            if fileURL == nil, let firstURL = AppDelegate.pendingURLs.first {
                // Open the first pending URL in this window
                fileURL = firstURL
                // Open remaining URLs in new windows
                for url in AppDelegate.pendingURLs.dropFirst() {
                    openWindow(value: url)
                }
                AppDelegate.pendingURLs.removeAll()
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .navigationTitle(fileURL?.lastPathComponent ?? "StillMD")
    }

    private func openFileInCurrentWindow() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md")!,
            UTType(filenameExtension: "markdown")!,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            fileURL = url
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

/// Shown when the app launches without a file.
struct EmptyStateView: View {
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("Markdown ファイルをドロップ")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("または")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button("ファイルを開く…") {
                onOpen()
            }
            .keyboardShortcut("o", modifiers: .command)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

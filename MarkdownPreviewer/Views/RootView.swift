import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Binding var fileURL: URL?
    @ObservedObject var windowManager: WindowManager
    @Environment(\.openWindow) private var openWindow

    @State private var isReady = false
    @State private var waitingForPendingURL = true

    var body: some View {
        Group {
            if let url = fileURL {
                PreviewView(fileURL: url, windowManager: windowManager)
            } else if !waitingForPendingURL {
                EmptyStateView {
                    openFileInCurrentWindow()
                }
            } else {
                Color.clear
            }
        }
        .opacity(isReady ? 1 : 0)
        .animation(.easeIn(duration: 0.15), value: isReady)
        .onAppear {
            windowManager.openWindowAction = openWindow

            if fileURL != nil {
                waitingForPendingURL = false
                isReady = true
                return
            }

            consumePendingURLs()

            if fileURL != nil {
                waitingForPendingURL = false
                isReady = true
                return
            }

            // Poll for pending URLs from AppDelegate (cold start timing)
            startPendingURLPolling()
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .navigationTitle(fileURL?.lastPathComponent ?? "stillmd")
    }

    private func startPendingURLPolling() {
        Task { @MainActor in
            for _ in 0..<20 { // up to 1 second
                try? await Task.sleep(for: .milliseconds(50))
                consumePendingURLs()
                if fileURL != nil {
                    waitingForPendingURL = false
                    withAnimation(.easeIn(duration: 0.15)) {
                        isReady = true
                    }
                    return
                }
            }
            // No pending URL arrived — show EmptyStateView
            waitingForPendingURL = false
            withAnimation(.easeIn(duration: 0.15)) {
                isReady = true
            }
        }
    }

    private func consumePendingURLs() {
        guard !AppDelegate.pendingURLs.isEmpty else { return }

        if fileURL == nil {
            fileURL = AppDelegate.pendingURLs.removeFirst()
        }
        for url in AppDelegate.pendingURLs {
            openWindow(value: url)
        }
        AppDelegate.pendingURLs.removeAll()
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

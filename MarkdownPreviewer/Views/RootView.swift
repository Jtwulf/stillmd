import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Binding var fileURL: URL?
    @ObservedObject var windowManager: WindowManager
    @Environment(\.openWindow) private var openWindow

    // Timer to check for pending URLs from AppDelegate.
    // application(_:open:) can fire slightly after onAppear.
    @State private var pendingCheckTimer: Timer?

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
            consumePendingURLs()

            // Keep checking for a short period in case application(_:open:)
            // fires after onAppear (common on cold start).
            pendingCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                Task { @MainActor in
                    consumePendingURLs()
                }
            }
            // Stop checking after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                pendingCheckTimer?.invalidate()
                pendingCheckTimer = nil
            }
        }
        .onDisappear {
            pendingCheckTimer?.invalidate()
            pendingCheckTimer = nil
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .navigationTitle(fileURL?.lastPathComponent ?? "StillMD")
    }

    private func consumePendingURLs() {
        guard !AppDelegate.pendingURLs.isEmpty else { return }

        if fileURL == nil {
            // This window has no file — use the first pending URL here
            fileURL = AppDelegate.pendingURLs.removeFirst()
        }
        // Open remaining URLs in new windows
        for url in AppDelegate.pendingURLs {
            openWindow(value: url)
        }
        AppDelegate.pendingURLs.removeAll()

        // Stop the timer once we've consumed URLs
        pendingCheckTimer?.invalidate()
        pendingCheckTimer = nil
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

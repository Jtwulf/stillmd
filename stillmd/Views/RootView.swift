import SwiftUI

struct RootView: View {
    @ObservedObject var documentSession: DocumentWindowSession
    @ObservedObject var windowManager: WindowManager
    @ObservedObject var pendingFileOpenCoordinator: PendingFileOpenCoordinator
    @Environment(\.documentChromeController) private var documentChromeController
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppPreferences.themeKey) private var themePreferenceRawValue =
        ThemePreference.system.rawValue

    @State private var isEmptyStatePresented = false
    @State private var isDropTargeted = false

    private var themePreference: ThemePreference {
        ThemePreference(rawValue: themePreferenceRawValue) ?? .system
    }

    private var resolvedColorScheme: ColorScheme {
        themePreference.colorScheme ?? colorScheme
    }

    private var windowTitle: String {
        documentSession.fileURL?.lastPathComponent ?? "stillmd"
    }

    var body: some View {
        ZStack {
            WindowSurfacePalette.background(for: resolvedColorScheme)
                .ignoresSafeArea()

            rootContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(themePreference.colorScheme)
        .onAppear {
            if documentSession.fileURL != nil {
                isEmptyStatePresented = false
            } else if consumePendingURLs() {
                isEmptyStatePresented = false
            } else {
                revealEmptyStateIfNeeded()
            }
            syncDocumentChrome()
        }
        .onChange(of: pendingFileOpenCoordinator.pendingChangeID) { _, _ in
            if consumePendingURLs() {
                isEmptyStatePresented = false
            }
            syncDocumentChrome()
        }
        .onChange(of: documentSession.fileURL) { _, _ in
            syncDocumentChrome()
        }
        .onChange(of: themePreferenceRawValue) { _, _ in
            syncDocumentChrome()
        }
        .onChange(of: colorScheme) { _, _ in
            syncDocumentChrome()
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        // Window title + chrome are driven by `DocumentWindowChromeController` on `NSWindow`.
        // Avoid `.navigationTitle` here: it syncs with AppKit titlebar and can undo unified chrome.
    }

    @ViewBuilder
    private var rootContent: some View {
        if let url = documentSession.fileURL {
            PreviewView(fileURL: url, windowManager: windowManager)
                .id(url.path)
        } else {
            EmptyStateView(
                onOpen: {
                    openFileInCurrentWindow()
                },
                isDropTargeted: isDropTargeted,
                isPresented: isEmptyStatePresented
            )
        }
    }

    private func syncDocumentChrome() {
        documentChromeController?.syncFromSwiftUI(
            title: windowTitle,
            colorScheme: resolvedColorScheme,
            fileURL: documentSession.fileURL?.standardizedFileURL,
            windowManager: windowManager
        )
    }

    private func revealEmptyStateIfNeeded() {
        Task { @MainActor in
            await Task.yield()

            if consumePendingURLs() {
                isEmptyStatePresented = false
                return
            }

            if !isEmptyStatePresented {
                isEmptyStatePresented = true
            }
        }
    }

    @discardableResult
    private func consumePendingURLs() -> Bool {
        let pendingURLs = pendingFileOpenCoordinator.drain()
        guard !pendingURLs.isEmpty else { return false }

        var remainingURLs = pendingURLs
        if documentSession.fileURL == nil, let initialURL = remainingURLs.first {
            documentSession.fileURL = initialURL
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
            documentSession.fileURL = url
            isEmptyStatePresented = false
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, FileValidation.isMarkdownFile(url) else { return }
                Task { @MainActor in
                    if self.documentSession.fileURL == nil {
                        self.documentSession.fileURL = url
                    } else {
                        self.windowManager.openFile(url)
                    }
                }
            }
        }
        return true
    }
}

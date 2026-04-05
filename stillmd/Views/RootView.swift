import SwiftUI

struct RootView: View {
    @ObservedObject var documentSession: DocumentWindowSession
    @ObservedObject var windowManager: WindowManager
    @ObservedObject var pendingFileOpenCoordinator: PendingFileOpenCoordinator
    @EnvironmentObject private var themeState: ThemeState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var findCommandBindings: FindCommandBindings
    @Environment(\.documentChromeController) private var documentChromeController

    /// `EmptyStateView` は初回表示だけ `windowEntrance` を通す。
    /// 背景は先に描画されるので、`false -> true` の遷移でも白抜けしない。
    @State private var isEmptyStatePresented = false
    @State private var emptyStateRevealTask: Task<Void, Never>?
    @State private var emptyStateRevealScheduleID = 0
    @State private var isDropTargeted = false

    private var resolvedColorScheme: ColorScheme {
        themeState.themePreference.resolvedColorScheme(using: colorScheme)
    }

    private var windowTitle: String {
        documentSession.fileURL?.lastPathComponent ?? "stillmd"
    }

    var body: some View {
        ZStack {
            WindowSurfacePalette.background(for: resolvedColorScheme)
                .ignoresSafeArea()

            rootContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(themeState.themePreference.colorScheme)
        // Keep command actions at the window root so the active document window owns shortcut state.
        .focusedSceneValue(\.toggleFindBarAction, findCommandBindings.toggleFindBarAction)
        .focusedSceneValue(\.findNextAction, findCommandBindings.findNextAction)
        .focusedSceneValue(\.findPreviousAction, findCommandBindings.findPreviousAction)
        .onAppear {
            if documentSession.fileURL != nil {
                emptyStateRevealTask?.cancel()
                emptyStateRevealTask = nil
                isEmptyStatePresented = false
            } else if consumePendingURLs() {
                emptyStateRevealTask?.cancel()
                emptyStateRevealTask = nil
                isEmptyStatePresented = false
            } else {
                scheduleEmptyStateReveal()
            }
            syncDocumentChrome()
        }
        .onChange(of: pendingFileOpenCoordinator.pendingChangeID) { _, _ in
            if consumePendingURLs() {
                emptyStateRevealTask?.cancel()
                emptyStateRevealTask = nil
                isEmptyStatePresented = false
            }
            syncDocumentChrome()
        }
        .onChange(of: documentSession.fileURL?.path ?? "") { _, _ in
            syncDocumentChrome()
        }
        .onChange(of: colorScheme) { _, _ in
            syncDocumentChrome()
        }
        .onDisappear {
            emptyStateRevealTask?.cancel()
            emptyStateRevealTask = nil
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
            PreviewView(
                fileURL: url,
                windowManager: windowManager,
                findCommandBindings: findCommandBindings
            )
                // New `PreviewView` + `StateObject` per file so URL changes reload the document and replay preview reveal.
                .id(url.standardizedFileURL.path)
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
        emptyStateRevealTask?.cancel()
        emptyStateRevealTask = nil
        let panel = NSOpenPanel()
        FileValidation.configureOpenPanel(panel, allowsMultipleSelection: false)
        if panel.runModal() == .OK, let url = panel.url {
            documentSession.fileURL = url
            isEmptyStatePresented = false
            syncDocumentChrome()
        }
    }

    private func scheduleEmptyStateReveal() {
        emptyStateRevealTask?.cancel()
        emptyStateRevealTask = nil

        emptyStateRevealScheduleID += 1
        let scheduleID = emptyStateRevealScheduleID
        isEmptyStatePresented = false

        if reduceMotion {
            isEmptyStatePresented = true
            return
        }

        emptyStateRevealTask = Task { @MainActor in
            await Task.yield()
            guard
                !Task.isCancelled,
                emptyStateRevealScheduleID == scheduleID,
                documentSession.fileURL == nil
            else { return }
            isEmptyStatePresented = true
            emptyStateRevealTask = nil
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

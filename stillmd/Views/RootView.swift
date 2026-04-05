import SwiftUI

struct RootView: View {
    @ObservedObject var documentSession: DocumentWindowSession
    @ObservedObject var windowManager: WindowManager
    @ObservedObject var pendingFileOpenCoordinator: PendingFileOpenCoordinator
    @EnvironmentObject private var themeState: ThemeState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.documentChromeController) private var documentChromeController
    @StateObject private var findPresentation = FindPresentationState()

    /// `EmptyStateView` は初回表示だけ `windowEntrance` を通す。
    /// 背景は先に描画されるので、`false -> true` の遷移でも白抜けしない。
    @State private var isEmptyStatePresented = false
    @State private var emptyStateRevealTask: Task<Void, Never>?
    @State private var emptyStateRevealScheduleID = 0
    @State private var isDropTargeted = false

    private var themePreference: ThemePreference {
        themeState.themePreference
    }

    private var windowTitle: String {
        documentSession.fileURL?.lastPathComponent ?? "stillmd"
    }

    var body: some View {
        ZStack {
            WindowSurfacePalette.background(for: themePreference.colorScheme)
                .ignoresSafeArea()

            rootContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(themePreference.colorScheme)
        // Keep command actions at the window root so shortcut state follows the document window,
        // not the transient PreviewView lifecycle.
        .focusedSceneValue(
            \.toggleFindBarAction,
            documentSession.fileURL == nil
                ? nil
                : FindAction(perform: { findPresentation.toggleFindBar(reduceMotion: reduceMotion) })
        )
        .focusedSceneValue(
            \.findNextAction,
            documentSession.fileURL == nil
                ? nil
                : FindAction(perform: { findPresentation.performFind(.next) })
        )
        .focusedSceneValue(
            \.findPreviousAction,
            documentSession.fileURL == nil
                ? nil
                : FindAction(perform: { findPresentation.performFind(.previous) })
        )
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
            if documentSession.fileURL == nil {
                findPresentation.resetForDocumentChange()
            }
            syncDocumentChrome()
        }
        .onChange(of: pendingFileOpenCoordinator.pendingChangeID) { _, _ in
            if consumePendingURLs() {
                emptyStateRevealTask?.cancel()
                emptyStateRevealTask = nil
                isEmptyStatePresented = false
            }
            if documentSession.fileURL == nil {
                findPresentation.resetForDocumentChange()
            }
            syncDocumentChrome()
        }
        .onChange(of: documentSession.fileURL?.path ?? "") { _, _ in
            findPresentation.resetForDocumentChange()
            syncDocumentChrome()
        }
        .onChange(of: themeState.themePreference) { _, _ in
            syncDocumentChrome()
        }
        .onDisappear {
            emptyStateRevealTask?.cancel()
            emptyStateRevealTask = nil
            findPresentation.resetForDocumentChange()
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
                findPresentation: findPresentation
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
            colorScheme: themePreference.colorScheme,
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

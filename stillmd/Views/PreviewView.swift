import SwiftUI

struct PreviewView: View {
    let fileURL: URL
    @ObservedObject var windowManager: WindowManager
    @ObservedObject var findPresentation: FindPresentationState
    @StateObject private var viewModel: PreviewViewModel
    @EnvironmentObject private var themeState: ThemeState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppPreferences.textScaleKey) private var textScale = AppPreferences.defaultTextScale

    @State private var isPreviewRevealed = false
    @State private var previewRevealScheduleID = 0
    @State private var webRevealFallbackTask: Task<Void, Never>?

    init(
        fileURL: URL,
        windowManager: WindowManager,
        findPresentation: FindPresentationState
    ) {
        self.fileURL = fileURL
        self.windowManager = windowManager
        self.findPresentation = findPresentation
        _viewModel = StateObject(wrappedValue: PreviewViewModel(fileURL: fileURL))
    }

    private var themePreference: ThemePreference {
        themeState.themePreference
    }

    private var shouldKeepPreviewVisible: Bool {
        viewModel.errorMessage == nil || !viewModel.markdownContent.isEmpty
    }

    /// エラー帯または検索バー表示中のみインセット内に実コンテンツを置く（非表示時は高さ 0 でプレースホルダ）。
    private var shouldShowTopChrome: Bool {
        findPresentation.isFindBarChromeReserved || (viewModel.errorMessage != nil && shouldKeepPreviewVisible)
    }

    private var previewRevealOpacity: Double {
        reduceMotion || isPreviewRevealed ? 1 : 0
    }

    private var previewRevealOffset: CGFloat {
        reduceMotion || isPreviewRevealed ? 0 : StillmdMotion.previewReveal.offsetY
    }

    var body: some View {
        // Use a plain `VStack` instead of `safeAreaInset`: inside `NSHostingView` + fullSizeContentView,
        // top safe-area math can collapse the web content to zero height (blank white preview).
        VStack(spacing: 0) {
            topChrome
            corePreview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Title is shown via `DocumentWindowChromeController` (titlebar accessory); avoid `.navigationTitle` fighting AppKit chrome.
        .onAppear {
            // Register this file in WindowManager for duplicate detection,
            // regardless of how the window was created (Finder, Dock, NSWorkspace, etc.)
            windowManager.registerFile(fileURL)
            viewModel.startWatching()
            // `shouldKeepPreviewVisible == true` のとき従来はここで schedule していなかったため、
            // `didCommit` が来ない環境だと `isPreviewRevealed` が永遠に false のまま真っ白になる。
            schedulePreviewReveal()
        }
        .onChange(of: shouldKeepPreviewVisible) { wasVisible, isVisible in
            if wasVisible, !isVisible {
                schedulePreviewReveal()
            }
        }
        .onDisappear {
            webRevealFallbackTask?.cancel()
            findPresentation.resetForDocumentChange()
            viewModel.stopWatching()
            windowManager.closeFile(fileURL)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .onExitCommand {
            guard findPresentation.isFindBarPresented else { return }
            findPresentation.dismissFindBar(reduceMotion: reduceMotion)
        }
    }

    @ViewBuilder
    private var corePreview: some View {
        Group {
            if shouldKeepPreviewVisible {
                MarkdownWebView(
                    markdownContent: viewModel.markdownContent,
                    containsMermaidFence: viewModel.containsMermaidFence,
                    baseURL: fileURL.deletingLastPathComponent(),
                    scrollPosition: $viewModel.scrollPosition,
                    themePreference: themePreference,
                    textScale: AppPreferences.clampedTextScale(textScale),
                    findQuery: findPresentation.findQuery,
                    findRequest: findPresentation.findRequest,
                    findStatus: $findPresentation.findStatus,
                    onInitialNavigationCommitted: onMarkdownWebViewInitialNavigationCommitted,
                    onWillLoadWebContent: { schedulePreviewReveal() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage {
                ErrorView(message: error)
            }
        }
        .opacity(previewRevealOpacity)
        .offset(y: previewRevealOffset)
        .animation(
            StillmdMotion.animation(for: StillmdMotion.previewReveal, reduceMotion: reduceMotion),
            value: isPreviewRevealed
        )
    }

    private func schedulePreviewReveal() {
        webRevealFallbackTask?.cancel()
        webRevealFallbackTask = nil

        previewRevealScheduleID += 1
        let scheduleID = previewRevealScheduleID
        if reduceMotion {
            isPreviewRevealed = true
            return
        }
        isPreviewRevealed = false

        if shouldKeepPreviewVisible {
            webRevealFallbackTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, previewRevealScheduleID == scheduleID, !isPreviewRevealed else { return }
                isPreviewRevealed = true
            }
        } else {
            Task { @MainActor in
                await Task.yield()
                guard previewRevealScheduleID == scheduleID else { return }
                isPreviewRevealed = true
            }
        }
    }

    private func onMarkdownWebViewInitialNavigationCommitted() {
        webRevealFallbackTask?.cancel()
        webRevealFallbackTask = nil
        let scheduleID = previewRevealScheduleID
        Task { @MainActor in
            guard previewRevealScheduleID == scheduleID else { return }
            isPreviewRevealed = true
        }
    }

    @ViewBuilder
    private var topChrome: some View {
        if shouldShowTopChrome {
            VStack(alignment: .trailing, spacing: 8) {
                if let error = viewModel.errorMessage, shouldKeepPreviewVisible {
                    InlineStatusBanner(message: error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if findPresentation.isFindBarPresented {
                    FindBar(
                        query: $findPresentation.findQuery,
                        status: findPresentation.findStatus,
                        onPrevious: { findPresentation.triggerFind(.previous) },
                        onNext: { findPresentation.triggerFind(.next) },
                        onClose: { findPresentation.dismissFindBar(reduceMotion: reduceMotion) }
                    )
                    .transition(StillmdMotion.findBarTransition(reduceMotion: reduceMotion))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .background(Color.clear)
        } else {
            Color.clear.frame(height: 0)
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

import SwiftUI

struct PreviewView: View {
    let fileURL: URL
    @ObservedObject var windowManager: WindowManager
    @StateObject private var viewModel: PreviewViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppPreferences.themeKey) private var themePreferenceRawValue =
        ThemePreference.system.rawValue
    @AppStorage(AppPreferences.textScaleKey) private var textScale = AppPreferences.defaultTextScale

    @State private var isFindBarPresented = false
    @State private var findQuery = ""
    @State private var findStatus = FindStatus.empty
    @State private var findRequest: FindRequest?
    @State private var findRequestID = 0
    @State private var isFindBarChromeReserved = false
    @State private var isDocumentLineNumbersPresented = false
    @State private var pendingFindResetTask: Task<Void, Never>?
    @State private var isPreviewRevealed = false
    @State private var previewRevealScheduleID = 0
    @State private var webRevealFallbackTask: Task<Void, Never>?

    init(fileURL: URL, windowManager: WindowManager) {
        self.fileURL = fileURL
        self.windowManager = windowManager
        _viewModel = StateObject(wrappedValue: PreviewViewModel(fileURL: fileURL))
    }

    private var themePreference: ThemePreference {
        ThemePreference(rawValue: themePreferenceRawValue) ?? .system
    }

    private var shouldKeepPreviewVisible: Bool {
        viewModel.errorMessage == nil || !viewModel.markdownContent.isEmpty
    }

    /// エラー帯または検索バー表示中のみインセット内に実コンテンツを置く（非表示時は高さ 0 でプレースホルダ）。
    private var shouldShowTopChrome: Bool {
        isFindBarChromeReserved || (viewModel.errorMessage != nil && shouldKeepPreviewVisible)
    }

    private var previewRevealOpacity: Double {
        reduceMotion ? 1 : (isPreviewRevealed ? 1 : 0)
    }

    private var previewRevealOffset: CGFloat {
        reduceMotion || isPreviewRevealed ? 0 : StillmdMotion.previewReveal.offsetY
    }

    var body: some View {
        corePreview
            .safeAreaInset(edge: .top, spacing: 0) {
                topChrome
            }
        // Title is shown via `DocumentWindowChromeController` (titlebar accessory); avoid `.navigationTitle` fighting AppKit chrome.
        .onAppear {
            // Register this file in WindowManager for duplicate detection,
            // regardless of how the window was created (Finder, Dock, NSWorkspace, etc.)
            windowManager.registerFile(fileURL)
            viewModel.startWatching()
            if !shouldKeepPreviewVisible {
                schedulePreviewReveal()
            }
        }
        .onChange(of: shouldKeepPreviewVisible) { wasVisible, isVisible in
            if wasVisible, !isVisible {
                schedulePreviewReveal()
            }
        }
        .onDisappear {
            pendingFindResetTask?.cancel()
            webRevealFallbackTask?.cancel()
            viewModel.stopWatching()
            windowManager.closeFile(fileURL)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .focusedSceneValue(\.toggleFindBarAction, FindAction(perform: toggleFindBar))
        .focusedSceneValue(
            \.toggleDocumentLineNumbersAction,
            FindAction(perform: toggleDocumentLineNumbers)
        )
        .focusedSceneValue(\.findNextAction, FindAction(perform: {
            if !isFindBarPresented {
                presentFindBar()
                return
            }
            triggerFind(.next)
        }))
        .focusedValue(\.findPreviousAction, FindAction(perform: {
            if !isFindBarPresented {
                presentFindBar()
                return
            }
            triggerFind(.previous)
        }))
        .onExitCommand {
            guard isFindBarPresented else { return }
            dismissFindBar()
        }
    }

    @ViewBuilder
    private var corePreview: some View {
        Group {
            if shouldKeepPreviewVisible {
                MarkdownWebView(
                    markdownContent: viewModel.markdownContent,
                    baseURL: fileURL.deletingLastPathComponent(),
                    scrollPosition: $viewModel.scrollPosition,
                    themePreference: themePreference,
                    textScale: AppPreferences.clampedTextScale(textScale),
                    documentLineNumbersVisible: isDocumentLineNumbersPresented,
                    findQuery: findQuery,
                    findRequest: findRequest,
                    findStatus: $findStatus,
                    onInitialNavigationCommitted: onMarkdownWebViewInitialNavigationCommitted,
                    onWillLoadWebContent: { schedulePreviewReveal() }
                )
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

                if isFindBarPresented {
                    FindBar(
                        query: $findQuery,
                        status: findStatus,
                        onPrevious: { triggerFind(.previous) },
                        onNext: { triggerFind(.next) },
                        onClose: dismissFindBar
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

    private func toggleFindBar() {
        if isFindBarPresented {
            dismissFindBar()
        } else {
            presentFindBar()
        }
    }

    private func presentFindBar() {
        guard !isFindBarPresented else { return }
        pendingFindResetTask?.cancel()
        runAnimation(StillmdMotion.animation(for: StillmdMotion.findBarInsertion, reduceMotion: reduceMotion)) {
            isFindBarChromeReserved = true
            isFindBarPresented = true
        }
    }

    private func dismissFindBar() {
        guard isFindBarPresented else { return }
        pendingFindResetTask?.cancel()
        runAnimation(StillmdMotion.animation(for: StillmdMotion.findBarRemoval, reduceMotion: reduceMotion)) {
            isFindBarPresented = false
        }
        scheduleFindReset()
    }

    private func toggleDocumentLineNumbers() {
        isDocumentLineNumbersPresented.toggle()
    }

    private func triggerFind(_ direction: FindDirection) {
        guard !findQuery.isEmpty else { return }
        findRequestID += 1
        findRequest = FindRequest(id: findRequestID, direction: direction)
    }

    private func scheduleFindReset() {
        let reset = {
            findQuery = ""
            findStatus = .empty
            findRequest = nil
        }

        guard !reduceMotion else {
            reset()
            isFindBarChromeReserved = false
            return
        }

        pendingFindResetTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: UInt64(StillmdMotion.findBarRemoval.duration * 1_000_000_000)
            )

            guard !Task.isCancelled, !isFindBarPresented else { return }
            reset()
            runAnimation(StillmdMotion.animation(for: StillmdMotion.findBarRemoval, reduceMotion: reduceMotion)) {
                isFindBarChromeReserved = false
            }
        }
    }

    private func runAnimation(_ animation: Animation?, updates: () -> Void) {
        if let animation {
            withAnimation(animation, updates)
        } else {
            updates()
        }
    }
}

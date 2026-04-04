import SwiftUI

struct PreviewView: View {
    let fileURL: URL
    @ObservedObject var windowManager: WindowManager
    @StateObject private var viewModel: PreviewViewModel
    @AppStorage(AppPreferences.themeKey) private var themePreferenceRawValue =
        ThemePreference.system.rawValue
    @AppStorage(AppPreferences.textScaleKey) private var textScale = AppPreferences.defaultTextScale

    @State private var isFindBarPresented = false
    @State private var findQuery = ""
    @State private var findStatus = FindStatus.empty
    @State private var findRequest: FindRequest?
    @State private var findRequestID = 0

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

    var body: some View {
        Group {
            if shouldKeepPreviewVisible {
                MarkdownWebView(
                    markdownContent: viewModel.markdownContent,
                    baseURL: fileURL.deletingLastPathComponent(),
                    scrollPosition: $viewModel.scrollPosition,
                    themePreference: themePreference,
                    textScale: AppPreferences.clampedTextScale(textScale),
                    findQuery: findQuery,
                    findRequest: findRequest,
                    findStatus: $findStatus
                )
            } else if let error = viewModel.errorMessage {
                ErrorView(message: error)
            }
        }
        .navigationTitle(fileURL.lastPathComponent)
        .background(WindowAccessor(url: fileURL.standardizedFileURL))
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 8) {
                if let error = viewModel.errorMessage, shouldKeepPreviewVisible {
                    InlineStatusBanner(message: error)
                }

                if isFindBarPresented {
                    HStack {
                        Spacer(minLength: 0)
                        FindBar(
                            query: $findQuery,
                            status: findStatus,
                            onPrevious: { triggerFind(.previous) },
                            onNext: { triggerFind(.next) },
                            onClose: dismissFindBar
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .onAppear {
            // Register this file in WindowManager for duplicate detection,
            // regardless of how the window was created (Finder, Dock, NSWorkspace, etc.)
            windowManager.registerFile(fileURL)
            viewModel.startWatching()
        }
        .onDisappear {
            viewModel.stopWatching()
            windowManager.closeFile(fileURL)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .onChange(of: isFindBarPresented) { _, isPresented in
            if !isPresented {
                findQuery = ""
                findStatus = .empty
            }
        }
        .focusedSceneValue(\.showFindBarAction, FindAction(perform: presentFindBar))
        .focusedSceneValue(\.findNextAction, FindAction(perform: {
            if !isFindBarPresented {
                presentFindBar()
                return
            }
            triggerFind(.next)
        }))
        .focusedSceneValue(\.findPreviousAction, FindAction(perform: {
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

    private func presentFindBar() {
        isFindBarPresented = true
    }

    private func dismissFindBar() {
        isFindBarPresented = false
        findRequest = nil
    }

    private func triggerFind(_ direction: FindDirection) {
        guard !findQuery.isEmpty else { return }
        findRequestID += 1
        findRequest = FindRequest(id: findRequestID, direction: direction)
    }
}

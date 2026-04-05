import Foundation
import Combine

@MainActor
class PreviewViewModel: ObservableObject {
    let fileURL: URL
    @Published var markdownContent: String = ""
    /// Derived when `markdownContent` changes; avoids re-scanning the full document on every WebView update.
    @Published private(set) var containsMermaidFence: Bool = false
    @Published var errorMessage: String? = nil
    @Published var scrollPosition: CGFloat = 0

    private var fileWatcher: FileWatcher?
    private var recoveryTask: Task<Void, Never>?
    private var modifiedDebounceTask: Task<Void, Never>?
    /// Coalesce rapid `.modified` events from editors (see `docs/plans/STILLMD_PERFORMANCE_REFACTOR_IMPLEMENTATION_PLAN.md`).
    private let modifiedDebounce: Duration = .milliseconds(100)
    /// `NSOpenPanel` / sandbox user-selected files need a matching `stopAccessing…` in `deinit`.
    private let holdsSecurityScopedAccess: Bool

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.holdsSecurityScopedAccess = fileURL.startAccessingSecurityScopedResource()
        loadFile()
    }

    deinit {
        if holdsSecurityScopedAccess {
            fileURL.stopAccessingSecurityScopedResource()
        }
    }

    func startWatching() {
        fileWatcher = FileWatcher(url: fileURL) { [weak self] event in
            Task { @MainActor in
                self?.handleFileEvent(event)
            }
        }
        fileWatcher?.start()
    }

    func stopWatching() {
        modifiedDebounceTask?.cancel()
        modifiedDebounceTask = nil
        loadFile()
        recoveryTask?.cancel()
        recoveryTask = nil
        fileWatcher?.stop()
        fileWatcher = nil
    }

    func loadFile() {
        do {
            let newContent = try String(contentsOf: fileURL, encoding: .utf8)
            if newContent != markdownContent {
                markdownContent = newContent
                containsMermaidFence = HTMLTemplate.containsMermaidFence(in: newContent)
            }
            errorMessage = nil
            recoveryTask?.cancel()
            recoveryTask = nil
        } catch {
            errorMessage = "ファイルを読み込めません: \(error.localizedDescription)"
        }
    }

    /// Exposed for tests (`@testable import`); production path is `FileWatcher` → `startWatching`.
    func handleFileEvent(_ event: FileWatcher.Event) {
        switch event {
        case .modified:
            scheduleDebouncedLoadFromDisk()
        case .deleted:
            errorMessage = "ファイルが見つかりません: \(fileURL.lastPathComponent)"
            startRecoveryPolling()
        }
    }

    private func scheduleDebouncedLoadFromDisk() {
        modifiedDebounceTask?.cancel()
        let delay = modifiedDebounce
        modifiedDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.loadFile()
        }
    }

    private func startRecoveryPolling() {
        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            let delays: [Duration] = [
                .milliseconds(250),
                .milliseconds(500),
                .seconds(1),
                .seconds(1),
                .seconds(2),
                .seconds(2),
                .seconds(3),
                .seconds(3),
            ]

            for delay in delays {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self else { return }

                if FileManager.default.isReadableFile(atPath: self.fileURL.path) {
                    self.fileWatcher?.stop()
                    self.fileWatcher?.start()
                    self.loadFile()
                    return
                }
            }
        }
    }
}

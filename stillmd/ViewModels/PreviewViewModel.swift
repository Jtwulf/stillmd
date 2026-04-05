import Foundation
import Combine

/// Markdown 本文と Mermaid 有無を一度に公開し、SwiftUI が中間状態の再描画を挟まないようにする。
struct PreviewMarkdownPayload: Equatable, Sendable {
    var content: String
    var containsMermaidFence: Bool

    static let empty = PreviewMarkdownPayload(content: "", containsMermaidFence: false)
}

@MainActor
class PreviewViewModel: ObservableObject {
    let fileURL: URL
    @Published private(set) var markdownPayload: PreviewMarkdownPayload = .empty
    @Published var errorMessage: String? = nil

    /// `markdownPayload` の投影（テスト・ビュー互換）。
    var markdownContent: String { markdownPayload.content }
    /// `markdownPayload` の投影。
    var containsMermaidFence: Bool { markdownPayload.containsMermaidFence }
    @Published var scrollPosition: CGFloat = 0

    private var fileWatcher: FileWatcher?
    private var recoveryTask: Task<Void, Never>?
    private var modifiedDebounceTask: Task<Void, Never>?
    /// Bumped on each new debounced schedule so a superseded task does not clear the active task or run `loadFile`.
    private var modifiedDebounceGeneration: UInt64 = 0
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
        modifiedDebounceTask?.cancel()
        recoveryTask?.cancel()
        if holdsSecurityScopedAccess {
            fileURL.stopAccessingSecurityScopedResource()
        }
    }

    func startWatching() {
        // `stopWatching` は保留デバウンスを捨てるため、再表示時に必ずディスクと同期する。
        loadFile()
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
        recoveryTask?.cancel()
        recoveryTask = nil
        fileWatcher?.stop()
        fileWatcher = nil
    }

    func loadFile() {
        do {
            let newContent = try String(contentsOf: fileURL, encoding: .utf8)
            if newContent != markdownPayload.content {
                markdownPayload = PreviewMarkdownPayload(
                    content: newContent,
                    containsMermaidFence: HTMLTemplate.containsMermaidFence(in: newContent)
                )
            }
            errorMessage = nil
            recoveryTask?.cancel()
            recoveryTask = nil
        } catch {
            errorMessage = "ファイルを読み込めません: \(error.localizedDescription)"
        }
    }

    /// 本番では `FileWatcher` のコールバック（`startWatching`）からのみ呼ばれる。`@testable` テストから直接触る。
    func handleFileEvent(_ event: FileWatcher.Event) {
        switch event {
        case .modified:
            scheduleDebouncedLoadFromDisk()
        case .deleted:
            modifiedDebounceTask?.cancel()
            modifiedDebounceTask = nil
            errorMessage = "ファイルが見つかりません: \(fileURL.lastPathComponent)"
            startRecoveryPolling()
        }
    }

    private func scheduleDebouncedLoadFromDisk() {
        modifiedDebounceTask?.cancel()
        modifiedDebounceGeneration += 1
        let generation = modifiedDebounceGeneration
        let delay = modifiedDebounce
        modifiedDebounceTask = Task { @MainActor [weak self] in
            defer {
                if let self, generation == self.modifiedDebounceGeneration {
                    self.modifiedDebounceTask = nil
                }
            }
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            guard generation == self.modifiedDebounceGeneration else { return }
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

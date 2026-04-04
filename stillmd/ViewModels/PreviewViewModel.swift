import Foundation
import Combine

@MainActor
class PreviewViewModel: ObservableObject {
    let fileURL: URL
    @Published var markdownContent: String = ""
    @Published var errorMessage: String? = nil
    @Published var scrollPosition: CGFloat = 0

    private var fileWatcher: FileWatcher?
    private var recoveryTask: Task<Void, Never>?

    init(fileURL: URL) {
        self.fileURL = fileURL
        loadFile()
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
            }
            errorMessage = nil
            recoveryTask?.cancel()
            recoveryTask = nil
        } catch {
            errorMessage = "ファイルを読み込めません: \(error.localizedDescription)"
        }
    }

    private func handleFileEvent(_ event: FileWatcher.Event) {
        switch event {
        case .modified:
            loadFile()
        case .deleted:
            errorMessage = "ファイルが見つかりません: \(fileURL.lastPathComponent)"
            startRecoveryPolling()
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

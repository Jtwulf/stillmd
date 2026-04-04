import Foundation
import Combine

@MainActor
class PreviewViewModel: ObservableObject {
    let fileURL: URL
    @Published var markdownContent: String = ""
    @Published var errorMessage: String? = nil
    @Published var scrollPosition: CGFloat = 0

    private var fileWatcher: FileWatcher?

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
        fileWatcher?.stop()
        fileWatcher = nil
    }

    func loadFile() {
        do {
            markdownContent = try String(contentsOf: fileURL, encoding: .utf8)
            errorMessage = nil
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
        }
    }
}

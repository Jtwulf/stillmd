import Foundation

@MainActor
final class PendingFileOpenCoordinator: ObservableObject {
    @Published private(set) var pendingChangeID: UInt = 0

    private var pendingURLs: [URL] = []

    func enqueue(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        pendingURLs.append(contentsOf: urls)
        pendingChangeID &+= 1
    }

    func drain() -> [URL] {
        defer { pendingURLs.removeAll() }
        return pendingURLs
    }
}

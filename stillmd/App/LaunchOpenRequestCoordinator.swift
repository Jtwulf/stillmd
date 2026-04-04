import Foundation

struct LaunchOpenRequestBatch: Equatable {
    let initialURL: URL
    let remainingURLs: [URL]
}

@MainActor
final class LaunchOpenRequestCoordinator {
    private var pendingURLs: [URL] = []

    var hasPendingURLs: Bool {
        !pendingURLs.isEmpty
    }

    func enqueue(_ urls: [URL]) {
        for url in urls {
            let standardizedURL = url.standardizedFileURL
            guard !pendingURLs.contains(standardizedURL) else { continue }
            pendingURLs.append(standardizedURL)
        }
    }

    func consumeBatch() -> LaunchOpenRequestBatch? {
        guard let initialURL = pendingURLs.first else { return nil }
        let remainingURLs = Array(pendingURLs.dropFirst())
        pendingURLs.removeAll()
        return LaunchOpenRequestBatch(initialURL: initialURL, remainingURLs: remainingURLs)
    }
}

import Foundation

final class FileWatcher: @unchecked Sendable {
    enum Event {
        case modified
        case deleted
    }

    private let url: URL
    private let callback: (Event) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let retryDelay: TimeInterval = 0.1
    private let maxRetries: Int = 3

    init(url: URL, callback: @escaping (Event) -> Void) {
        self.url = url
        self.callback = callback
    }

    func start() {
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            callback(.deleted)
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: .global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) {
                self.handleDeleteOrRename()
            } else if flags.contains(.write) {
                self.handleWrite()
            }
        }

        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }

        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func handleWrite() {
        readWithRetry(attempt: 0)
    }

    private func readWithRetry(attempt: Int) {
        if FileManager.default.isReadableFile(atPath: url.path) {
            callback(.modified)
        } else if attempt < maxRetries {
            DispatchQueue.global().asyncAfter(deadline: .now() + retryDelay) {
                self.readWithRetry(attempt: attempt + 1)
            }
        } else {
            callback(.deleted)
        }
    }

    private func handleDeleteOrRename() {
        // Editors often save by deleting + creating the file.
        // Wait briefly then re-check existence.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            if FileManager.default.fileExists(atPath: self.url.path) {
                // File was re-created — restart monitoring
                self.stop()
                self.start()
                self.callback(.modified)
            } else {
                self.callback(.deleted)
            }
        }
    }

    deinit {
        stop()
    }
}

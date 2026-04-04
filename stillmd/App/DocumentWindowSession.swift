import Foundation

/// Per-window document URL state; owned by `StillmdDocumentWindow` for lifetime tied to the window.
@MainActor
final class DocumentWindowSession: ObservableObject {
    @Published var fileURL: URL?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL
    }
}

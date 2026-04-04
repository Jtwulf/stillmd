import SwiftUI

private struct DocumentChromeControllerKey: EnvironmentKey {
    static let defaultValue: DocumentWindowChromeController? = nil
}

extension EnvironmentValues {
    var documentChromeController: DocumentWindowChromeController? {
        get { self[DocumentChromeControllerKey.self] }
        set { self[DocumentChromeControllerKey.self] = newValue }
    }
}

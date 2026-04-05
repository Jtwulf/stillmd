import Foundation
import SwiftUI

@MainActor
final class FindPresentationState: ObservableObject {
    @Published var isFindBarPresented = false
    @Published var findQuery = ""
    @Published var findStatus = FindStatus.empty
    @Published var findRequest: FindRequest?
    @Published var isFindBarChromeReserved = false

    private var findRequestID = 0
    private var pendingFindResetTask: Task<Void, Never>?

    func toggleFindBar(reduceMotion: Bool) {
        if isFindBarPresented {
            dismissFindBar(reduceMotion: reduceMotion)
        } else {
            presentFindBar()
        }
    }

    func performFind(_ direction: FindDirection) {
        if !isFindBarPresented {
            presentFindBar()
            return
        }

        triggerFind(direction)
    }

    func presentFindBar() {
        guard !isFindBarPresented else { return }

        pendingFindResetTask?.cancel()
        pendingFindResetTask = nil
        isFindBarChromeReserved = true
        isFindBarPresented = true
    }

    func dismissFindBar(reduceMotion: Bool) {
        guard isFindBarPresented else { return }

        isFindBarPresented = false
        scheduleFindReset(reduceMotion: reduceMotion)
    }

    func triggerFind(_ direction: FindDirection) {
        guard !findQuery.isEmpty else { return }

        findRequestID += 1
        findRequest = FindRequest(id: findRequestID, direction: direction)
    }

    func resetForDocumentChange() {
        pendingFindResetTask?.cancel()
        pendingFindResetTask = nil
        findRequestID = 0
        isFindBarPresented = false
        isFindBarChromeReserved = false
        findQuery = ""
        findStatus = .empty
        findRequest = nil
    }

    private func scheduleFindReset(reduceMotion: Bool) {
        pendingFindResetTask?.cancel()
        pendingFindResetTask = nil

        guard !reduceMotion else {
            resetFindState()
            isFindBarChromeReserved = false
            return
        }

        pendingFindResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(StillmdMotion.findBarRemoval.duration * 1_000_000_000)
            )

            guard let self, !Task.isCancelled, !self.isFindBarPresented else { return }
            self.resetFindState()
            self.isFindBarChromeReserved = false
            self.pendingFindResetTask = nil
        }
    }

    private func resetFindState() {
        findQuery = ""
        findStatus = .empty
        findRequest = nil
    }
}

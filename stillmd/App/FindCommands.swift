import SwiftUI

struct FindAction {
    let perform: () -> Void
}

@MainActor
final class FindCommandBindings: ObservableObject {
    @Published var toggleFindBarAction: FindAction?
    @Published var toggleDocumentLineNumbersAction: FindAction?
    @Published var findNextAction: FindAction?
    @Published var findPreviousAction: FindAction?

    func installPreviewActions(
        toggleFindBar: @escaping () -> Void,
        toggleDocumentLineNumbers: @escaping () -> Void,
        findNext: @escaping () -> Void,
        findPrevious: @escaping () -> Void
    ) {
        toggleFindBarAction = FindAction(perform: toggleFindBar)
        toggleDocumentLineNumbersAction = FindAction(perform: toggleDocumentLineNumbers)
        findNextAction = FindAction(perform: findNext)
        findPreviousAction = FindAction(perform: findPrevious)
    }

    func clearPreviewActions() {
        toggleFindBarAction = nil
        toggleDocumentLineNumbersAction = nil
        findNextAction = nil
        findPreviousAction = nil
    }
}

private struct ToggleFindBarActionKey: FocusedValueKey {
    typealias Value = FindAction
}

private struct ToggleDocumentLineNumbersActionKey: FocusedValueKey {
    typealias Value = FindAction
}

private struct FindNextActionKey: FocusedValueKey {
    typealias Value = FindAction
}

private struct FindPreviousActionKey: FocusedValueKey {
    typealias Value = FindAction
}

extension FocusedValues {
    var toggleFindBarAction: FindAction? {
        get { self[ToggleFindBarActionKey.self] }
        set { self[ToggleFindBarActionKey.self] = newValue }
    }

    var toggleDocumentLineNumbersAction: FindAction? {
        get { self[ToggleDocumentLineNumbersActionKey.self] }
        set { self[ToggleDocumentLineNumbersActionKey.self] = newValue }
    }

    var findNextAction: FindAction? {
        get { self[FindNextActionKey.self] }
        set { self[FindNextActionKey.self] = newValue }
    }

    var findPreviousAction: FindAction? {
        get { self[FindPreviousActionKey.self] }
        set { self[FindPreviousActionKey.self] = newValue }
    }
}

struct FindCommands: Commands {
    @FocusedValue(\.toggleFindBarAction) private var toggleFindBarAction
    @FocusedValue(\.toggleDocumentLineNumbersAction) private var toggleDocumentLineNumbersAction
    @FocusedValue(\.findNextAction) private var findNextAction
    @FocusedValue(\.findPreviousAction) private var findPreviousAction

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find…") {
                toggleFindBarAction?.perform()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(toggleFindBarAction == nil)

            Button("Line Numbers") {
                toggleDocumentLineNumbersAction?.perform()
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(toggleDocumentLineNumbersAction == nil)

            Button("Find Next") {
                findNextAction?.perform()
            }
            .keyboardShortcut("g", modifiers: .command)
            .disabled(findNextAction == nil)

            Button("Find Previous") {
                findPreviousAction?.perform()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(findPreviousAction == nil)
        }
    }
}

import SwiftUI

struct FindAction {
    let perform: () -> Void
}

private struct ShowFindBarActionKey: FocusedValueKey {
    typealias Value = FindAction
}

private struct FindNextActionKey: FocusedValueKey {
    typealias Value = FindAction
}

private struct FindPreviousActionKey: FocusedValueKey {
    typealias Value = FindAction
}

extension FocusedValues {
    var showFindBarAction: FindAction? {
        get { self[ShowFindBarActionKey.self] }
        set { self[ShowFindBarActionKey.self] = newValue }
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
    @FocusedValue(\.showFindBarAction) private var showFindBarAction
    @FocusedValue(\.findNextAction) private var findNextAction
    @FocusedValue(\.findPreviousAction) private var findPreviousAction

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find…") {
                showFindBarAction?.perform()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(showFindBarAction == nil)

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

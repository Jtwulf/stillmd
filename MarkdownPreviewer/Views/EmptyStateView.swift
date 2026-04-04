import SwiftUI

struct EmptyStateView: View {
    let onOpen: () -> Void
    let isDropTargeted: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 14) {
            Text("Open Markdown")
                .font(.title3.weight(.medium))
                .foregroundStyle(isDropTargeted ? .primary : .secondary)

            Button("Open") {
                onOpen()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("o", modifiers: .command)
        }
        .frame(maxWidth: 280)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: -28)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.14),
            value: isDropTargeted
        )
    }
}

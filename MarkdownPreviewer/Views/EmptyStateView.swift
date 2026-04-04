import SwiftUI

struct EmptyStateView: View {
    let onOpen: () -> Void
    let isDropTargeted: Bool
    let isPresented: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var revealOpacity: Double {
        reduceMotion ? 1 : (isPresented ? 1 : 0)
    }

    private var revealOffset: CGFloat {
        reduceMotion || isPresented ? 0 : StillmdMotion.emptyReveal.offsetY
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)

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
        .opacity(revealOpacity)
        .offset(y: -12 + revealOffset)
        .animation(
            StillmdMotion.animation(for: StillmdMotion.emptyReveal, reduceMotion: reduceMotion),
            value: isPresented
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.14),
            value: isDropTargeted
        )
    }
}

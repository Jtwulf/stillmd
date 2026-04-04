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
        VStack(spacing: 18) {
            StillmdEmptyStateMark(isDropTargeted: isDropTargeted)

            VStack(spacing: 8) {
                Text("Read Markdown, still.")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(isDropTargeted ? .primary : .secondary)
                    .multilineTextAlignment(.center)

                Button("Open") {
                    onOpen()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("o", modifiers: .command)
            }
        }
        .frame(maxWidth: 320)
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(revealOpacity)
        .offset(y: -10 + revealOffset)
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

private struct StillmdEmptyStateMark: View {
    let isDropTargeted: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var markFill: Color {
        switch colorScheme {
        case .dark:
            return Color.primary.opacity(isDropTargeted ? 0.07 : 0.045)
        default:
            return Color.primary.opacity(isDropTargeted ? 0.05 : 0.03)
        }
    }

    private var markStroke: Color {
        switch colorScheme {
        case .dark:
            return Color.primary.opacity(isDropTargeted ? 0.16 : 0.10)
        default:
            return Color.primary.opacity(isDropTargeted ? 0.12 : 0.08)
        }
    }

    private var lineColor: Color {
        .secondary.opacity(isDropTargeted ? 0.88 : 0.68)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(markFill)

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(markStroke, lineWidth: 1)

            VStack(alignment: .leading, spacing: 7) {
                Capsule(style: .continuous)
                    .fill(lineColor.opacity(0.88))
                    .frame(width: 44, height: 5)

                Capsule(style: .continuous)
                    .fill(lineColor.opacity(0.64))
                    .frame(width: 31, height: 5)

                HStack(spacing: 6) {
                    Text("</>")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(lineColor.opacity(0.82))

                    Capsule(style: .continuous)
                        .fill(lineColor.opacity(0.50))
                        .frame(width: 26, height: 5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
        }
        .frame(width: 96, height: 96)
        .accessibilityHidden(true)
    }
}

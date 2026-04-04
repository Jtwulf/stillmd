import SwiftUI

enum FindDirection: String {
    case next
    case previous
}

struct FindRequest: Equatable {
    let id: Int
    let direction: FindDirection
}

struct FindStatus: Equatable {
    var matchCount = 0
    var currentIndex = -1

    static let empty = FindStatus()

    var displayText: String {
        guard matchCount > 0, currentIndex >= 0 else {
            return "結果なし"
        }
        return "\(currentIndex + 1) / \(matchCount)"
    }
}

struct FindBar: View {
    @Binding var query: String
    let status: FindStatus
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onClose: () -> Void

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("本文を検索", text: $query)
                .textFieldStyle(.plain)
                .frame(minWidth: 220)
                .focused($isFieldFocused)
                .onSubmit(onNext)

            Text(status.displayText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 56, alignment: .trailing)

            Button(action: onPrevious) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .disabled(query.isEmpty || status.matchCount == 0)

            Button(action: onNext) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .disabled(query.isEmpty || status.matchCount == 0)

            Divider()
                .frame(height: 14)

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        .onAppear {
            isFieldFocused = true
        }
    }
}

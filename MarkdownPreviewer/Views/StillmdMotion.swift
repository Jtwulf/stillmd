import SwiftUI

struct MotionSpec {
    let duration: Double
    let offsetY: CGFloat
}

enum StillmdMotion {
    static let emptyReveal = MotionSpec(duration: 0.18, offsetY: 5)
    static let findBarInsertion = MotionSpec(duration: 0.14, offsetY: -4)
    static let findBarRemoval = MotionSpec(duration: 0.10, offsetY: -3)

    static func animation(for spec: MotionSpec, reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return .easeOut(duration: spec.duration)
    }

    static func findBarTransition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }

        return .asymmetric(
            insertion: .modifier(
                active: OffsetOpacityModifier(opacity: 0, offsetY: findBarInsertion.offsetY),
                identity: OffsetOpacityModifier(opacity: 1, offsetY: 0)
            ),
            removal: .modifier(
                active: OffsetOpacityModifier(opacity: 0, offsetY: findBarRemoval.offsetY),
                identity: OffsetOpacityModifier(opacity: 1, offsetY: 0)
            )
        )
    }
}

private struct OffsetOpacityModifier: ViewModifier {
    let opacity: Double
    let offsetY: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .offset(y: offsetY)
    }
}

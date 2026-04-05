import AppKit

enum WindowPlacementCalculator {
    static let cascadeStep = CGSize(width: 24, height: 24)
    static let edgeMargin: CGFloat = 24

    static func centeredFrame(windowSize: NSSize, in visibleFrame: NSRect) -> NSRect {
        NSRect(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.midY - windowSize.height / 2,
            width: windowSize.width,
            height: windowSize.height
        )
    }

    static func cascadedFrame(
        referenceFrame: NSRect?,
        visibleFrame: NSRect,
        windowSize: NSSize
    ) -> NSRect {
        let centeredFrame = centeredFrame(windowSize: windowSize, in: visibleFrame)
        guard let referenceFrame else { return centeredFrame }

        let cascadedFrame = referenceFrame.offsetBy(dx: cascadeStep.width, dy: -cascadeStep.height)
        let isOutsideVisibleFrame =
            cascadedFrame.minX < visibleFrame.minX + edgeMargin ||
            cascadedFrame.maxX > visibleFrame.maxX - edgeMargin ||
            cascadedFrame.minY < visibleFrame.minY + edgeMargin ||
            cascadedFrame.maxY > visibleFrame.maxY - edgeMargin

        return isOutsideVisibleFrame ? centeredFrame : cascadedFrame
    }
}

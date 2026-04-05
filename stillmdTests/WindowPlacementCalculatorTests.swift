import AppKit
import Testing
@testable import stillmd

@Suite("Window placement calculator")
struct WindowPlacementCalculatorTests {
    @Test("cascades down and to the right when room is available")
    func cascadesDownAndRightWhenRoomIsAvailable() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let windowSize = NSSize(width: WindowDefaults.defaultWidth, height: WindowDefaults.defaultHeight)
        let referenceFrame = WindowPlacementCalculator.centeredFrame(windowSize: windowSize, in: visibleFrame)

        let nextFrame = WindowPlacementCalculator.cascadedFrame(
            referenceFrame: referenceFrame,
            visibleFrame: visibleFrame,
            windowSize: windowSize
        )

        #expect(nextFrame.origin.x == referenceFrame.origin.x + WindowPlacementCalculator.cascadeStep.width)
        #expect(nextFrame.origin.y == referenceFrame.origin.y - WindowPlacementCalculator.cascadeStep.height)
        #expect(nextFrame.size == windowSize)
    }

    @Test("returns centered frame when the next step would hit the visible edge")
    func returnsCenteredFrameWhenTheNextStepWouldHitTheVisibleEdge() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let windowSize = NSSize(width: WindowDefaults.defaultWidth, height: WindowDefaults.defaultHeight)
        let referenceFrame = NSRect(
            x: visibleFrame.maxX - windowSize.width - 8,
            y: visibleFrame.minY + 120,
            width: windowSize.width,
            height: windowSize.height
        )

        let nextFrame = WindowPlacementCalculator.cascadedFrame(
            referenceFrame: referenceFrame,
            visibleFrame: visibleFrame,
            windowSize: windowSize
        )

        let centeredFrame = WindowPlacementCalculator.centeredFrame(windowSize: windowSize, in: visibleFrame)
        #expect(nextFrame == centeredFrame)
    }

    @Test("returns centered frame when there is no reference frame")
    func returnsCenteredFrameWhenThereIsNoReferenceFrame() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let windowSize = NSSize(width: WindowDefaults.defaultWidth, height: WindowDefaults.defaultHeight)

        let nextFrame = WindowPlacementCalculator.cascadedFrame(
            referenceFrame: nil,
            visibleFrame: visibleFrame,
            windowSize: windowSize
        )

        let centeredFrame = WindowPlacementCalculator.centeredFrame(windowSize: windowSize, in: visibleFrame)
        #expect(nextFrame == centeredFrame)
    }
}

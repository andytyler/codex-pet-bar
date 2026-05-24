import Testing
@testable import CodexPetBarCore

@Suite("Pet animation frame clock")
struct PetAnimationFrameClockTests {
    @Test("walking animation visits every frame before looping")
    func walkingAnimationVisitsEveryFrameBeforeLooping() {
        let metadata = PetAtlasMetadata.rowsByState[.runningRight]
        var clock = PetAnimationFrameClock()
        var displayedFrames: [Int] = []

        for _ in 0..<8 {
            displayedFrames.append(clock.frameIndex)
            clock.advanceAfterDisplay(deltaTime: 0.14, metadata: metadata, frameCount: 8)
        }

        #expect(displayedFrames == Array(0...7))
    }

    @Test("walking animation holds the planted final frame")
    func walkingAnimationHoldsPlantedFinalFrame() {
        let metadata = PetAtlasMetadata.rowsByState[.runningRight]
        var clock = PetAnimationFrameClock(frameIndex: 7)

        clock.advanceAfterDisplay(deltaTime: 0.14, metadata: metadata, frameCount: 8)

        #expect(clock.frameIndex == 7)

        clock.advanceAfterDisplay(deltaTime: 0.08, metadata: metadata, frameCount: 8)

        #expect(clock.frameIndex == 0)
    }
}

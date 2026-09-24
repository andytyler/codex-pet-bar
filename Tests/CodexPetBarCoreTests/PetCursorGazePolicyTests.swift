import Testing
@testable import CodexPetBarCore

@Suite("Pet cursor gaze policy")
struct PetCursorGazePolicyTests {
    @Test("only an automatic, motion-enabled, inactive v2 pet tracks the cursor")
    func cursorTrackingEligibility() {
        #expect(shouldTrack())
        #expect(!shouldTrack(spriteVersionNumber: 1))
        #expect(!shouldTrack(activity: .running))
        #expect(!shouldTrack(activity: .reviewing))
        #expect(!shouldTrack(activity: .failed))
        #expect(!shouldTrack(hasActiveThreads: true))
        #expect(!shouldTrack(manualAnimationState: .idle))
        #expect(!shouldTrack(hasReaction: true))
        #expect(!shouldTrack(approvalRequested: true))
        #expect(!shouldTrack(reduceMotion: true))
    }

    @Test("same gaze sector does not request redundant rendering")
    func duplicateSectorsAreSuppressed() {
        let first = PetCursorGazePolicy.update(
            x: 0,
            y: 10,
            previousHeadingIndex: nil
        )
        let sameSector = PetCursorGazePolicy.update(
            x: 0.2,
            y: 10,
            previousHeadingIndex: first.headingIndex
        )

        #expect(first == .init(headingIndex: 0, shouldRender: true))
        #expect(sameSector == .init(headingIndex: 0, shouldRender: false))
    }

    @Test("entering the one pixel deadzone clears an existing gaze once")
    func deadzoneClearsGazeOnce() {
        let cleared = PetCursorGazePolicy.update(
            x: 0.6,
            y: 0.8,
            previousHeadingIndex: 4
        )
        let remainsClear = PetCursorGazePolicy.update(
            x: 0,
            y: 0,
            previousHeadingIndex: cleared.headingIndex
        )

        #expect(cleared == .init(headingIndex: nil, shouldRender: true))
        #expect(remainsClear == .init(headingIndex: nil, shouldRender: false))
    }

    @Test("coalescing delay caps cursor renders without delaying an idle first event")
    func cursorRenderCoalescingDelay() {
        #expect(PetCursorGazePolicy.coalescingDelay(
            lastRenderTime: nil,
            now: 20,
            minimumInterval: 0.05
        ) == 0)
        #expect(PetCursorGazePolicy.coalescingDelay(
            lastRenderTime: 20,
            now: 20.02,
            minimumInterval: 0.05
        ) > 0.029)
        #expect(PetCursorGazePolicy.coalescingDelay(
            lastRenderTime: 20,
            now: 20.06,
            minimumInterval: 0.05
        ) == 0)
    }

    private func shouldTrack(
        spriteVersionNumber: Int = 2,
        activity: CodexActivity = .idle,
        hasActiveThreads: Bool = false,
        manualAnimationState: PetAnimationState? = nil,
        hasReaction: Bool = false,
        approvalRequested: Bool = false,
        reduceMotion: Bool = false
    ) -> Bool {
        PetCursorGazePolicy.shouldTrack(
            spriteVersionNumber: spriteVersionNumber,
            activity: activity,
            hasActiveThreads: hasActiveThreads,
            manualAnimationState: manualAnimationState,
            hasReaction: hasReaction,
            approvalRequested: approvalRequested,
            reduceMotion: reduceMotion
        )
    }
}

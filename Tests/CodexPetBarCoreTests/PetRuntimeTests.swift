import Testing
@testable import CodexPetBarCore

@Suite("Pet runtime")
struct PetRuntimeTests {
    @Test("running activity advances position and uses directional running states")
    func runningActivityAdvancesPositionAndUsesDirectionalRunningStates() {
        var runtime = PetRuntime(playfieldWidth: 80, spriteWidth: 18, motionSpeed: 18)

        let firstFrame = runtime.tick(
            activity: .running,
            approvalRequested: false,
            deltaTime: 1.0
        )

        #expect(firstFrame.positionX == 49)
        #expect(firstFrame.animationState == .runningRight)

        let secondFrame = runtime.tick(
            activity: .running,
            approvalRequested: false,
            deltaTime: 10.0
        )

        #expect(secondFrame.positionX == 62)
        #expect(secondFrame.animationState == .runningLeft)
    }

    @Test("approval request triggers a waving action-camera pulse even when activity later runs")
    func approvalRequestTriggersWavingActionCameraPulseEvenWhenActivityLaterRuns() {
        var runtime = PetRuntime(playfieldWidth: 80, spriteWidth: 18, motionSpeed: 18)

        let approvalFrame = runtime.tick(
            activity: .running,
            approvalRequested: true,
            deltaTime: 0.1
        )

        #expect(approvalFrame.animationState == .waving)
        #expect(approvalFrame.scale == 1)
        #expect(approvalFrame.positionX == 31)
        #expect(approvalFrame.isApprovalPresentationActive)

        let followupFrame = runtime.tick(
            activity: .running,
            approvalRequested: false,
            deltaTime: 0.9
        )

        #expect(followupFrame.animationState == .waving)
        #expect(followupFrame.scale == 2.6)
        #expect(followupFrame.isApprovalPresentationActive)
    }

    @Test("approval pulse recenters before zooming from an edge")
    func approvalPulseRecentersBeforeZoomingFromAnEdge() {
        var runtime = PetRuntime(playfieldWidth: 80, spriteWidth: 18, motionSpeed: 18)
        _ = runtime.tick(activity: .running, approvalRequested: false, deltaTime: 10)

        let walkingToCenter = runtime.tick(activity: .running, approvalRequested: true, deltaTime: 0.1)

        #expect(walkingToCenter.animationState == .runningLeft)
        #expect(walkingToCenter.scale == 1)

        let centeredWaving = runtime.tick(activity: .running, approvalRequested: false, deltaTime: 10)

        #expect(centeredWaving.animationState == .waving)
        #expect(centeredWaving.positionX == 31)
        #expect(centeredWaving.scale == 1)
        #expect(centeredWaving.isApprovalPresentationActive)

        let zoomedWaving = runtime.tick(activity: .running, approvalRequested: false, deltaTime: 0.9)
        #expect(zoomedWaving.animationState == .waving)
        #expect(zoomedWaving.scale == 2.6)
    }

    @Test("cancelling attention immediately restores activity presentation")
    func cancellingAttentionRestoresActivityPresentation() {
        var runtime = PetRuntime(playfieldWidth: 80, spriteWidth: 18, motionSpeed: 18)
        _ = runtime.tick(activity: .running, approvalRequested: true, deltaTime: 0.1)
        _ = runtime.tick(activity: .running, approvalRequested: false, deltaTime: 0.9)

        runtime.cancelApprovalPulse()
        let restored = runtime.tick(
            activity: .failed,
            approvalRequested: false,
            deltaTime: 0
        )

        #expect(restored.animationState == .failed)
        #expect(restored.scale == 1)
        #expect(!restored.isApprovalPulseActive)
        #expect(!restored.isApprovalPresentationActive)
    }

    @Test("runtime frame clock honors row timing metadata")
    func runtimeFrameClockHonorsRowTimingMetadata() {
        var runtime = PetRuntime(
            playfieldWidth: 80,
            spriteWidth: 18,
            motionSpeed: 18,
            frameIndex: 7,
            animationState: .runningRight
        )

        let heldFrame = runtime.tick(
            activity: .running,
            approvalRequested: false,
            deltaTime: 0.14
        )

        #expect(heldFrame.frameIndex == 7)

        let advancedFrame = runtime.tick(
            activity: .running,
            approvalRequested: false,
            deltaTime: 0.08
        )

        #expect(advancedFrame.frameIndex == 0)
    }

    @Test("one shot reaction overrides automatic activity before resuming")
    func oneShotReactionOverridesAutomaticActivityBeforeResuming() {
        var runtime = PetRuntime(playfieldWidth: 80, spriteWidth: 18, motionSpeed: 18)

        let reactionFrame = runtime.tick(
            activity: .running,
            reactionState: .waving,
            approvalRequested: false,
            deltaTime: 0.14
        )

        #expect(reactionFrame.animationState == .waving)
        #expect(reactionFrame.positionX == 31)

        let resumedFrame = runtime.tick(
            activity: .running,
            reactionState: nil,
            approvalRequested: false,
            deltaTime: 0.14
        )

        #expect(resumedFrame.animationState == .runningRight)
    }
}

import Testing
@testable import CodexPetBarCore

@Suite("Pet motion")
struct PetMotionTests {
    @Test("pet walks across the playfield and uses directional running states")
    func walksAcrossPlayfield() {
        var motion = PetMotion(playfieldWidth: 80, spriteWidth: 18)

        motion.startWalking(direction: .right)
        motion.advance(deltaTime: 1.0)

        #expect(motion.positionX == 49)
        #expect(motion.animationState == .runningRight)
    }

    @Test("pet bounces when it reaches a playfield edge")
    func bouncesAtPlayfieldEdge() {
        var motion = PetMotion(playfieldWidth: 42, spriteWidth: 18)

        motion.startWalking(direction: .right)
        motion.advance(deltaTime: 10.0)

        #expect(motion.positionX == 24)
        #expect(motion.direction == .left)
        #expect(motion.animationState == .runningLeft)
    }

    @Test("pet can walk to the trailing edge without bouncing")
    func walksToTrailingEdgeWithoutBouncing() {
        var motion = PetMotion(playfieldWidth: 42, spriteWidth: 18)

        let reached = motion.advanceTowardTrailingEdge(deltaTime: 10.0)

        #expect(reached)
        #expect(motion.positionX == 24)
        #expect(motion.direction == .right)
        #expect(!motion.isWalking)
    }

    @Test("pet can walk until only half remains visible at the trailing edge")
    func walksUntilHalfVisibleAtTrailingEdge() {
        var motion = PetMotion(playfieldWidth: 42, spriteWidth: 18)

        let reached = motion.advanceTowardTrailingEdge(deltaTime: 10.0, visibleFraction: 0.5)

        #expect(reached)
        #expect(motion.positionX == 33)
        #expect(motion.direction == .right)
        #expect(!motion.isWalking)
    }

    @Test("ticker pet stands still after reaching the edge when nothing is running")
    func tickerPetStandsStillAtEdgeWhenNothingIsRunning() {
        let state = PetMotion.tickerAnimationState(reachedTrailingEdge: true, runningThreadCount: 0)

        #expect(state == .idle)
    }

    @Test("pet walks to the playfield center before attention reactions")
    func walksToPlayfieldCenterBeforeAttentionReactions() {
        var motion = PetMotion(playfieldWidth: 80, spriteWidth: 20)

        motion.startWalking(direction: .left)
        motion.advance(deltaTime: 10.0)

        let reachedOnFirstStep = motion.advanceTowardCenter(deltaTime: 0.5)
        #expect(!reachedOnFirstStep)
        #expect(motion.direction == .right)
        #expect(motion.isWalking)

        let reachedCenter = motion.advanceTowardCenter(deltaTime: 10.0)
        #expect(reachedCenter)
        #expect(motion.positionX == 30)
        #expect(!motion.isWalking)
    }

    @Test("pet already at center does not wander before attention reactions")
    func alreadyCenteredPetDoesNotWanderBeforeAttentionReactions() {
        var motion = PetMotion(playfieldWidth: 80, spriteWidth: 20)

        let reachedCenter = motion.advanceTowardCenter(deltaTime: 0.5)

        #expect(reachedCenter)
        #expect(motion.positionX == 30)
        #expect(!motion.isWalking)
    }

    @Test("pet pauses where it is when walking stops")
    func pausesWhereItIsWhenWalkingStops() {
        var motion = PetMotion(playfieldWidth: 80, spriteWidth: 18)

        motion.startWalking(direction: .right)
        motion.advance(deltaTime: 1.0)
        motion.stopWalking()
        motion.advance(deltaTime: 1.0)

        #expect(motion.positionX == 49)
        #expect(motion.animationState == .waiting)
    }
}

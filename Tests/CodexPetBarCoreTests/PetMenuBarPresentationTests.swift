import Testing
@testable import CodexPetBarCore

@Suite("Pet menu bar presentation")
struct PetMenuBarPresentationTests {
    @Test("only an automatic idle pet with no outstanding work sleeps")
    func automaticIdleWithoutWorkSleeps() {
        #expect(PetMenuBarPresentation.shouldSleep(
            activity: .idle,
            activeTaskCount: 0,
            manualAnimationState: nil,
            hasReaction: false,
            hasAttention: false
        ))
    }

    @Test("non-idle activity never sleeps even before the task count arrives")
    func activityPreventsFalseIdle() {
        for activity in [CodexActivity.running, .reviewing, .listening, .failed] {
            #expect(!PetMenuBarPresentation.shouldSleep(
                activity: activity,
                activeTaskCount: 0,
                manualAnimationState: nil,
                hasReaction: false,
                hasAttention: false
            ))
        }
    }

    @Test("active tasks and unresolved reactions prevent sleeping")
    func outstandingWorkPreventsSleeping() {
        for count in [1, 10, Int.max] {
            #expect(!PetMenuBarPresentation.shouldSleep(
                activity: .idle,
                activeTaskCount: count,
                manualAnimationState: nil,
                hasReaction: false,
                hasAttention: false
            ))
        }
        #expect(!PetMenuBarPresentation.shouldSleep(
            activity: .idle,
            activeTaskCount: 0,
            manualAnimationState: nil,
            hasReaction: true,
            hasAttention: false
        ))
        #expect(!PetMenuBarPresentation.shouldSleep(
            activity: .idle,
            activeTaskCount: 0,
            manualAnimationState: nil,
            hasReaction: false,
            hasAttention: true
        ))
    }

    @Test("manual animation selection takes precedence over sleeping")
    func manualAnimationPreventsSleeping() {
        for animation in PetAnimationState.allCases {
            #expect(!PetMenuBarPresentation.shouldSleep(
                activity: .idle,
                activeTaskCount: 0,
                manualAnimationState: animation,
                hasReaction: false,
                hasAttention: false
            ))
        }
    }

    @Test("verified pets use their closed-eye idle frame with a safe fallback")
    func sleepingFrameSelection() {
        for petID in ["goblin", "grumble", "mini-gandalf-the-grey"] {
            #expect(PetMenuBarPresentation.sleepingFrameIndex(petID: petID, frameCount: 6) == 2)
            #expect(PetMenuBarPresentation.sleepingFrameIndex(petID: petID, frameCount: 3) == 2)
            for count in [0, 1, 2] {
                #expect(PetMenuBarPresentation.sleepingFrameIndex(petID: petID, frameCount: count) == 0)
            }
        }
        #expect(PetMenuBarPresentation.sleepingFrameIndex(petID: "custom-pet", frameCount: 6) == 0)
        #expect(PetMenuBarPresentation.sleepingFrameIndex(petID: nil, frameCount: 6) == 0)
    }

    @Test("work opens a runway and idle returns to the pet's own width")
    func workChangesWidth() {
        for preferred in [44.0, 56.0, 102.0] {
            let sleeping = PetMenuBarPresentation.petWidth(spriteWidth: 20.3, preferredWidth: preferred, isRunning: false)
            let running = PetMenuBarPresentation.petWidth(spriteWidth: 20.3, preferredWidth: preferred, isRunning: true)
            #expect(sleeping == 25)
            #expect(running > sleeping)
            #expect(running <= 64)
            var runtime = PetRuntime(playfieldWidth: running, spriteWidth: 20.3, motionSpeed: 18)
            let first = runtime.tick(activity: .running, approvalRequested: false, deltaTime: 0.14)
            let later = runtime.tick(activity: .running, approvalRequested: false, deltaTime: 0.28)
            #expect(first.positionX != later.positionX)
            #expect(later.animationState == .runningRight || later.animationState == .runningLeft)
        }
    }

    @Test("provider layout fits the icons with fixed, readable spacing")
    func compactProviderLayout() {
        #expect(PetMenuBarPresentation.providerWidth(count: 0) == 0)
        #expect(PetMenuBarPresentation.providerWidth(count: 1) == 18)
        #expect(PetMenuBarPresentation.providerWidth(count: 3) == 56)
        #expect(PetMenuBarPresentation.providerWidth(count: Int.max) == 56)
        #expect(PetMenuBarPresentation.contentWidth(petWidth: 25, providerCount: 0) == 25)
        #expect(PetMenuBarPresentation.contentWidth(petWidth: 25, providerCount: 1) == 43)
        #expect(PetMenuBarPresentation.contentWidth(petWidth: 64, providerCount: 1) == 82)
        #expect(PetMenuBarPresentation.contentWidth(petWidth: 64, providerCount: 3) == 120)
    }

    @Test("sleeping width removes empty playfield without shrinking the sprite")
    func sleepingWidthPreservesSprite() {
        #expect(PetMenuBarPresentation.sleepingWidth(spriteWidth: 20.3) == 25)
        #expect(PetMenuBarPresentation.sleepingWidth(spriteWidth: 22) == 26)
        for spriteWidth in [12.0, 20.3, 22.0, 35.8] {
            #expect(PetMenuBarPresentation.sleepingWidth(spriteWidth: spriteWidth) - 4 >= spriteWidth)
        }
    }
}

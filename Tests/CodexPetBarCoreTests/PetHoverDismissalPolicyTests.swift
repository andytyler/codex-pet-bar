import Testing
@testable import CodexPetBarCore

@Suite("Hover fade ownership")
struct PetHoverDismissalPolicyTests {
    @Test("Reentering either surface invalidates an in-flight fade completion")
    func fadeReentry() {
        var policy = PetHoverDismissalPolicy()
        let first = policy.beginFade()
        let canceled = policy.cancelFade()
        let staleCompletion = policy.finishFade(first, pointerOwnsSurface: false)
        let second = policy.beginFade()
        let staleCompletionDuringNewFade = policy.finishFade(first, pointerOwnsSurface: false)
        let currentCompletion = policy.finishFade(second, pointerOwnsSurface: false)
        #expect(canceled)
        #expect(!staleCompletion)
        #expect(!staleCompletionDuringNewFade)
        #expect(currentCompletion)
    }

    @Test("Final pointer check protects ownership even before an enter event is delivered")
    func pointerAtCompletion() {
        var policy = PetHoverDismissalPolicy()
        let token = policy.beginFade()
        let completion = policy.finishFade(token, pointerOwnsSurface: true)
        #expect(!completion)
        #expect(!policy.isFading)
        let repeatedCompletion = policy.finishFade(token, pointerOwnsSurface: false)
        #expect(!repeatedCompletion)
    }
}

import Testing
@testable import CodexPetBarCore

@Suite("Pet attention presentation queue")
struct PetAttentionPresentationQueueTests {
    @Test("startup immediately presents preexisting attention in deterministic provider order")
    func startupPresentsPreexistingAttention() {
        let cursor = scope(.cursor, "cursor-review", .reviewing)
        let codex = scope(.codex, "codex-review", .reviewing)
        let ignored = scope(.claude, "claude-running", .running)
        var queue = PetAttentionPresentationQueue()

        queue.synchronize(scopes: [cursor, ignored, codex])

        #expect(queue.activeScope == codex)
        #expect(queue.activeProvider == .codex)
    }

    @Test("concurrent Codex Claude and Cursor reviews each get a turn")
    func concurrentProvidersEachGetATurn() {
        let codex = scope(.codex, "codex", .reviewing)
        let claude = scope(.claude, "claude", .reviewing)
        let cursor = scope(.cursor, "cursor", .reviewing)
        var queue = PetAttentionPresentationQueue()
        queue.synchronize(scopes: [cursor, claude, codex])

        #expect(queue.activeScope == codex)

        queue.presentationDidFinish()
        #expect(queue.activeScope == claude)

        queue.presentationDidFinish()
        #expect(queue.activeScope == cursor)

        queue.presentationDidFinish()
        #expect(queue.activeScope == codex)
        #expect(queue.activePresentationIsRepeat)
    }

    @Test("reviewing attention repeats for as long as its scope remains")
    func reviewingAttentionRepeats() {
        let review = scope(.claude, "review", .reviewing)
        var queue = PetAttentionPresentationQueue()
        queue.synchronize(scopes: [review])

        queue.presentationDidFinish()
        #expect(queue.activeScope == review)
        #expect(queue.activePresentationIsRepeat)

        queue.presentationDidFinish()
        #expect(queue.activeScope == review)
    }

    @Test("new attention preempts a repeat reminder")
    func newAttentionPreemptsRepeatReminder() {
        let codex = scope(.codex, "codex", .reviewing)
        let cursor = scope(.cursor, "cursor", .failed)
        var queue = PetAttentionPresentationQueue()
        queue.synchronize(scopes: [codex])
        queue.presentationDidFinish()
        #expect(queue.activePresentationIsRepeat)

        queue.synchronize(scopes: [codex, cursor])

        #expect(queue.activeScope == cursor)
        #expect(!queue.activePresentationIsRepeat)
        queue.presentationDidFinish()
        #expect(queue.activeScope == codex)
        #expect(queue.activePresentationIsRepeat)
    }

    @Test("a new scope is queued only once across repeated synchronizations")
    func newScopeIsQueuedOnlyOnce() {
        let review = scope(.codex, "review", .reviewing)
        let failure = scope(.cursor, "failure", .failed)
        var queue = PetAttentionPresentationQueue()
        queue.synchronize(scopes: [review])

        queue.synchronize(scopes: [review, failure])
        queue.synchronize(scopes: [failure, review])
        queue.synchronize(scopes: [review, failure])

        queue.presentationDidFinish()
        #expect(queue.activeScope == failure)

        queue.presentationDidFinish()
        #expect(queue.activeScope == review)
    }

    @Test("failed attention is one shot until the scope leaves and reenters")
    func failedAttentionRequiresReentryToRepeat() {
        let failure = scope(.cursor, "failure", .failed)
        var queue = PetAttentionPresentationQueue()
        queue.synchronize(scopes: [failure])

        #expect(queue.activeScope == failure)
        queue.presentationDidFinish()
        #expect(queue.activeScope == nil)

        queue.synchronize(scopes: [failure])
        #expect(queue.activeScope == nil)

        queue.synchronize(scopes: [])
        queue.synchronize(scopes: [failure])
        #expect(queue.activeScope == failure)
    }

    @Test("removed active and pending scopes are cleared immediately")
    func removedScopesAreCleared() {
        let codex = scope(.codex, "codex", .reviewing)
        let claude = scope(.claude, "claude", .reviewing)
        let cursor = scope(.cursor, "cursor", .failed)
        var queue = PetAttentionPresentationQueue()
        queue.synchronize(scopes: [codex, claude, cursor])

        queue.synchronize(scopes: [claude])
        #expect(queue.activeScope == claude)

        queue.presentationDidFinish()
        #expect(queue.activeScope == claude)
    }

    @Test("same-provider scopes cycle by stable identity rather than input order")
    func sameProviderScopesUseStableIdentityOrder() {
        let alpha = scope(.claude, "alpha", .reviewing)
        let zulu = scope(.claude, "zulu", .reviewing)
        var queue = PetAttentionPresentationQueue()
        queue.synchronize(scopes: [zulu, alpha])

        #expect(queue.activeScope == alpha)
        queue.presentationDidFinish()
        #expect(queue.activeScope == zulu)
    }

    @Test("changing attention activity replaces the prior presentation")
    func activityChangeReplacesPresentation() {
        let review = scope(.codex, "same", .reviewing)
        let failure = scope(.codex, "same", .failed)
        var queue = PetAttentionPresentationQueue()
        queue.synchronize(scopes: [review])

        queue.synchronize(scopes: [failure])
        #expect(queue.activeScope == failure)

        queue.presentationDidFinish()
        #expect(queue.activeScope == nil)
    }

    private func scope(
        _ provider: PetProvider,
        _ identity: String,
        _ activity: CodexActivity
    ) -> CodexPetActiveScope {
        CodexPetActiveScope(
            provider: provider,
            scopedIdentity: identity,
            activity: activity
        )
    }
}

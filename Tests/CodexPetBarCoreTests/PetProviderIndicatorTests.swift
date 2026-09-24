import Testing
@testable import CodexPetBarCore

@Suite("Pet provider indicators")
struct PetProviderIndicatorTests {
    @Test("no tasks means no provider indicators")
    func emptyScopesHaveNoIndicators() {
        #expect(PetMenuBarPresentation.providerIndicators(for: []).isEmpty)
    }

    @Test("repeated tasks collapse to one indicator in canonical provider order")
    func repeatedTasksUseCanonicalProviderOrder() {
        let cursor = scope(.cursor, "cursor-first", .running)
        let claude = scope(.claude, "claude-first", .running)
        let codex = scope(.codex, "codex-first", .running)
        let scopes = [
            cursor, claude, codex,
            scope(.codex, "codex-second", .running),
            scope(.cursor, "cursor-second", .running)
        ]

        let indicators = PetMenuBarPresentation.providerIndicators(for: scopes)

        #expect(indicators == [codex, claude, cursor])
        #expect(indicators.map(\.provider) == PetProvider.allCases)
        #expect(scopes.count == 5)
        #expect(indicators.count == 3)
    }

    @Test("each higher urgency wins regardless of task input order")
    func strongestActivityWins() {
        let activities: [CodexActivity] = [.idle, .listening, .running, .reviewing, .failed]
        for weakerIndex in 0..<(activities.count - 1) {
            for strongerIndex in (weakerIndex + 1)..<activities.count {
                let weaker = scope(.codex, "weaker", activities[weakerIndex])
                let stronger = scope(.codex, "stronger", activities[strongerIndex])
                #expect(PetMenuBarPresentation.providerIndicators(for: [weaker, stronger]) == [stronger])
                #expect(PetMenuBarPresentation.providerIndicators(for: [stronger, weaker]) == [stronger])
            }
        }
    }

    @Test("equal urgency preserves the first task identity")
    func equalUrgencyKeepsFirstScope() {
        for activity in CodexActivity.allCases {
            let first = scope(.claude, "first", activity)
            let second = scope(.claude, "second", activity)
            #expect(PetMenuBarPresentation.providerIndicators(for: [first, second]) == [first])
            #expect(PetMenuBarPresentation.providerIndicators(for: [second, first]) == [second])
        }
    }

    @Test("urgency is selected independently for each provider")
    func eachProviderRetainsItsStrongestScope() {
        let codexFailure = scope(.codex, "codex-failure", .failed)
        let claudeReview = scope(.claude, "claude-review", .reviewing)
        let cursorRunning = scope(.cursor, "cursor-running", .running)
        let scopes = [
            scope(.cursor, "cursor-idle", .idle),
            scope(.claude, "claude-running", .running),
            codexFailure,
            scope(.codex, "codex-review", .reviewing),
            claudeReview,
            scope(.codex, "codex-running", .running),
            cursorRunning,
            scope(.cursor, "cursor-listening", .listening),
            scope(.codex, "codex-followup", .listening),
            scope(.claude, "claude-idle", .idle),
            scope(.claude, "claude-second-running", .running)
        ]

        let indicators = PetMenuBarPresentation.providerIndicators(for: scopes)

        #expect(indicators == [codexFailure, claudeReview, cursorRunning])
        #expect(scopes.count == 11)
        #expect(scopes.filter { $0.provider == .codex }.count == 4)
    }

    @Test("providers without tasks receive no placeholder indicator")
    func absentProvidersAreOmitted() {
        let cursor = scope(.cursor, "cursor-only", .listening)
        #expect(PetMenuBarPresentation.providerIndicators(for: [cursor]) == [cursor])
    }

    private func scope(_ provider: PetProvider, _ identity: String, _ activity: CodexActivity) -> CodexPetActiveScope {
        CodexPetActiveScope(provider: provider, scopedIdentity: identity, activity: activity)
    }
}

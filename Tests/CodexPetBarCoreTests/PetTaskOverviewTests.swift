import Testing
@testable import CodexPetBarCore

@Suite("Task overview titles")
struct PetTaskOverviewTests {
    @Test("waiting work remains visible during another task's completion")
    func waitingBeatsCompletionAndWorkCount() {
        let scopes = [scope("running", .running), scope("permission", .reviewing)]

        #expect(PetTaskOverview.title(scopes: scopes, showsCompletion: true, currentActivity: .running)
                == "1 task needs you")
    }

    @Test("failures and waiting tasks share the attention count across providers")
    func attentionCountCombinesProviders() {
        let scopes = [
            scope("same-session-name", .reviewing, provider: .codex),
            scope("same-session-name", .failed, provider: .claude),
            scope("running", .running, provider: .cursor),
        ]

        #expect(PetTaskOverview.title(scopes: scopes, showsCompletion: true, currentActivity: .reviewing)
                == "2 tasks need you")
    }

    @Test("running scope counts ignore idle history and supersede completion")
    func workingCountUsesActiveScopes() {
        #expect(PetTaskOverview.title(scopes: [scope("one", .running), scope("history", .idle)],
                                      showsCompletion: true, currentActivity: .running) == "1 task working")
        #expect(PetTaskOverview.title(scopes: [scope("one", .running), scope("two", .running)],
                                      showsCompletion: false, currentActivity: .running) == "2 tasks working")
    }

    @Test("listening is distinguished from working")
    func listeningIsNotWorking() {
        #expect(PetTaskOverview.title(scopes: [scope("one", .listening), scope("two", .listening)],
                                      showsCompletion: false, currentActivity: .listening) == "Listening")
        #expect(PetTaskOverview.title(scopes: [scope("one", .listening), scope("two", .running)],
                                      showsCompletion: false, currentActivity: .running) == "2 active tasks")
    }

    @Test("a quiet pet only announces completion while the completion signal is present")
    func quietAndCompletionTitles() {
        #expect(PetTaskOverview.title(scopes: [], showsCompletion: false, currentActivity: .idle) == "All quiet")
        #expect(PetTaskOverview.title(scopes: [], showsCompletion: true, currentActivity: .idle) == "All done")
    }

    @Test("manual activity keeps an attention signal without inventing task counts")
    func activityFallbacks() {
        #expect(PetTaskOverview.title(scopes: [], showsCompletion: true, currentActivity: .reviewing)
                == "Needs your attention")
        #expect(PetTaskOverview.title(scopes: [], showsCompletion: true, currentActivity: .failed)
                == "Needs your attention")
        #expect(PetTaskOverview.title(scopes: [], showsCompletion: false, currentActivity: .running) == "Working")
        #expect(PetTaskOverview.title(scopes: [], showsCompletion: false, currentActivity: .listening) == "Listening")
    }

    private func scope(
        _ identity: String,
        _ activity: CodexActivity,
        provider: PetProvider = .codex
    ) -> CodexPetActiveScope {
        CodexPetActiveScope(provider: provider, scopedIdentity: identity, activity: activity)
    }
}

import Foundation
import Testing
@testable import CodexPetBarCore

@Suite("Cached task reconciliation freshness")
struct PetTaskReconciliationFreshnessTests {
    @Test("cached running cards retire when their existing provider lease expires",
          arguments: [PetProvider.codex, .claude, .cursor])
    func runningCardsFollowExpiredSnapshot(provider: PetProvider) throws {
        let events = [CodexPetEvent(kind: "tool_started", timestamp: 100,
                                   provider: provider, sessionID: "session")]
        let lifetime: TimeInterval = provider == .codex ? CodexPetActivityFreshness.codexRunningWindow : 30 * 60
        let beforeExpiry = Date(timeIntervalSince1970: 100 + lifetime - 1)
        let afterExpiry = Date(timeIntervalSince1970: 100 + lifetime + 1)
        let cached = PetTaskSummaryBuilder.providerTasks(events: events, now: beforeExpiry)
        #expect(cached.first?.status == .running)
        let expired = CodexPetEventLog.snapshot(events: events, now: afterExpiry)
        #expect(expired.activeScopes.isEmpty)

        let reconciled = try #require(PetTaskSummaryBuilder.reconciling(
            tasks: cached, snapshot: expired, now: afterExpiry).first)

        #expect(reconciled.status == .recent)
        #expect(reconciled.detail == "Recent activity")
        #expect(reconciled.sourceID == "session")
        #expect(reconciled.updatedAt == cached.first?.updatedAt)
    }

    @Test("a cached discovered task retires after the existing tool-completion grace")
    func discoveryGraceExpiresCachedCard() throws {
        let events = [CodexPetEvent(kind: "tool_succeeded", timestamp: 100,
                                   provider: .codex, sessionID: "discovered")]
        let cached = PetTaskSummaryBuilder.providerTasks(events: events, now: Date(timeIntervalSince1970: 130))
        #expect(cached.first?.status == .running)
        let expired = CodexPetEventLog.snapshot(events: events, now: Date(timeIntervalSince1970: 131))

        let reconciled = try #require(PetTaskSummaryBuilder.reconciling(tasks: cached, snapshot: expired).first)

        #expect(expired.activeScopes.isEmpty)
        #expect(reconciled.status == .recent)
    }

    @Test("all cached active states require a matching current scope",
          arguments: [PetTaskStatus.running, .waiting, .failed])
    func missingActiveStatesBecomeRecent(status: PetTaskStatus) throws {
        let cached = task(status: status)
        let reconciled = try #require(PetTaskSummaryBuilder.reconciling(tasks: [cached], snapshot: emptySnapshot).first)

        #expect(reconciled.status == .recent)
        #expect(reconciled.title == cached.title)
        #expect(reconciled.project == cached.project)
        #expect(reconciled.deepLinkURL == cached.deepLinkURL)
    }

    @Test("fresh rollout evidence keeps work active after hook evidence expires")
    func freshRolloutRetainsRunningTask() throws {
        let events = [CodexPetEvent(kind: "tool_started", timestamp: 100,
                                   provider: .codex, sessionID: "session")]
        let cached = PetTaskSummaryBuilder.providerTasks(events: events, now: Date(timeIntervalSince1970: 110))
        let now = Date(timeIntervalSince1970: 100 + 6 * 60 * 60 + 1)
        let expiredHooks = CodexPetEventLog.snapshot(events: events, now: now)
        #expect(expiredHooks.activeScopes.isEmpty)
        let merged = CodexPetActivityReconciler.merging(snapshot: expiredHooks,
            runningCodexScopes: [CodexRolloutActivityScope(sessionID: "session", modificationDate: now)])

        let reconciled = try #require(PetTaskSummaryBuilder.reconciling(tasks: cached, snapshot: merged, now: now).first)

        #expect(reconciled.status == .running)
        #expect(reconciled.updatedAt == now)
    }

    @Test("recorded completion and recent history survive an empty active snapshot",
          arguments: [PetTaskStatus.completed, .recent])
    func inactiveHistoryIsPreserved(status: PetTaskStatus) {
        let cached = task(status: status, detail: "Verified the navigation changes")

        #expect(PetTaskSummaryBuilder.reconciling(tasks: [cached], snapshot: emptySnapshot) == [cached])
    }

    @Test("explicit Codex completion still closes a cached running child")
    func verifiedParentCompletionWins() throws {
        let child = PetTaskSummary(sourceID: "child", navigationSourceID: "session", provider: .codex,
            title: "Child work", detail: "Working", status: .running, project: .other,
            updatedAt: Date(timeIntervalSince1970: 100), deepLinkURL: CodexThreadDeepLink.url(forThreadID: "session"))
        let reconciled = try #require(PetTaskSummaryBuilder.reconciling(tasks: [child], snapshot: emptySnapshot,
            completedCodexScopes: [CodexRolloutActivityScope(sessionID: "session")]).first)

        #expect(reconciled.status == .completed)
        #expect(reconciled.navigationSourceID == "session")
        #expect(reconciled.detail == "Finished recently")
    }

    @Test("another provider using the same source ID cannot keep an expired card running")
    func providerScopesRemainIndependent() throws {
        let cached = task(status: .running)
        let snapshot = CodexPetActivitySnapshot(activity: .running, activeSessionIDs: ["cursor:session"],
            activeScopeCount: 1, activeScopes: [CodexPetActiveScope(provider: .cursor,
                scopedIdentity: "cursor:session", activity: .running, sessionID: "session")])
        let reconciled = PetTaskSummaryBuilder.reconciling(tasks: [cached], snapshot: snapshot)

        #expect(reconciled.first { $0.provider == .codex }?.status == .recent)
        #expect(reconciled.first { $0.provider == .cursor }?.status == .running)
    }

    private var emptySnapshot: CodexPetActivitySnapshot {
        CodexPetActivitySnapshot(activity: nil, activeSessionIDs: [], activeScopeCount: 0)
    }

    private func task(status: PetTaskStatus, detail: String = "Working") -> PetTaskSummary {
        PetTaskSummary(sourceID: "session", navigationSourceID: "session", provider: .codex,
            title: "Improve the pet bar", detail: detail, status: status,
            project: .derived(fromWorkspace: "/example/pet-bar"), updatedAt: Date(timeIntervalSince1970: 100),
            deepLinkURL: CodexThreadDeepLink.url(forThreadID: "session"))
    }
}

import Foundation
import Testing
@testable import CodexPetBarCore

@Suite("Provider task identities")
struct ProviderTaskIdentityTests {
    private let now = Date(timeIntervalSince1970: 10_000)

    @Test("concurrent unnamed sessions in one project have stable distinguishable names",
          arguments: [PetProvider.claude, .cursor])
    func concurrentSessionsHaveDistinctNames(provider: PetProvider) {
        let sessionIDs = [
            "019f842c-c312-7332-afec-d21d912578b7",
            "019f842c-c312-7332-afec-d21d912578b8",
        ]
        let events = sessionIDs.map { event(provider: provider, sessionID: $0) }
        let tasks = PetTaskSummaryBuilder.providerTasks(events: events, now: now)
        let reversed = PetTaskSummaryBuilder.providerTasks(events: events.reversed(), now: now)

        #expect(tasks.count == 2)
        #expect(Set(tasks.map(\.title)).count == 2)
        #expect(tasks.allSatisfy { $0.title.contains(" · …") && $0.title.count < 35 })
        #expect(tasks.allSatisfy { $0.title.hasSuffix(String($0.sourceID.suffix(8))) })
        #expect(tasks.allSatisfy { $0.status == .running && $0.project.name == "shared-project" })
        #expect(Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.title) })
            == Dictionary(uniqueKeysWithValues: reversed.map { ($0.id, $0.title) }))
    }

    @Test("same source identifier remains visibly namespaced by provider")
    func matchingIDsAcrossProvidersRemainDistinct() {
        let events = [PetProvider.claude, .cursor].map { event(provider: $0, sessionID: "worker-a") }
        let tasks = PetTaskSummaryBuilder.providerTasks(events: events, now: now)

        #expect(Set(tasks.map(\.title)) == ["Claude Code · worker-a", "Cursor · worker-a"])
        #expect(Set(tasks.map(\.id)).count == 2)
    }

    @Test("child run names use their own identity while navigation keeps the parent")
    func childNamesDoNotCollapseToParent() {
        let events = ["worker-a", "worker-b"].map { child in
            event(provider: .claude, sessionID: "shared-parent:subagent:\(child)", parentSessionID: "shared-parent")
        }
        let tasks = PetTaskSummaryBuilder.providerTasks(events: events, now: now)

        #expect(Set(tasks.map(\.title)) == ["Claude Code · …worker-a", "Claude Code · …worker-b"])
        #expect(tasks.allSatisfy { $0.navigationSourceID == "shared-parent" })
        #expect(tasks.allSatisfy { $0.status == .running && $0.deepLinkURL == nil })
    }

    @Test("snapshot-only tasks use the same identity as subsequent event-backed tasks",
          arguments: [PetProvider.claude, .cursor])
    func snapshotAndEventTitlesAgree(provider: PetProvider) throws {
        let sessionID = "019f842c-c312-7332-afec-d21d912578b7"
        let scope = CodexPetActiveScope(provider: provider, scopedIdentity: sessionID,
            activity: .reviewing, sessionID: sessionID, parentSessionID: "parent-session",
            workspace: "/example/shared-project")
        let snapshot = CodexPetActivitySnapshot(activity: .reviewing, activeSessionIDs: [sessionID],
            activeScopeCount: 1, activeScopes: [scope])
        let synthesized = try #require(PetTaskSummaryBuilder.reconciling(
            tasks: [], snapshot: snapshot, now: now).first)
        let eventBacked = try #require(PetTaskSummaryBuilder.providerTasks(events: [
            event(provider: provider, sessionID: sessionID, kind: "permission_requested",
                  parentSessionID: "parent-session"),
        ], now: now).first)

        #expect(synthesized.title == eventBacked.title)
        #expect(synthesized.status == .waiting)
        #expect(synthesized.navigationSourceID == "parent-session")
        #expect(synthesized.project.name == "shared-project")
    }

    @Test("assistant activity remains detail rather than becoming an invented task name")
    func assistantSummaryDoesNotReplaceIdentity() throws {
        let summary = "Implemented the adapter and verified the tests"
        let task = try #require(PetTaskSummaryBuilder.providerTasks(events: [
            CodexPetEvent(kind: "stopped", timestamp: 9_995, provider: .claude,
                workspace: "/example/shared-project", sessionID: "session-one", assistantSummary: summary),
        ], now: now).first)

        #expect(task.title == "Claude Code · session-one")
        #expect(task.detail == summary)
        #expect(task.status == .completed)
    }

    @Test("real supplied task titles survive status reconciliation")
    func explicitTitlesArePreserved() throws {
        let task = PetTaskSummary(sourceID: "session-one", provider: .cursor,
            title: "Fix keyboard navigation", detail: "Working", status: .running,
            project: .other, updatedAt: now)
        let scope = CodexPetActiveScope(provider: .cursor, scopedIdentity: "session-one",
            activity: .reviewing, sessionID: "session-one")
        let snapshot = CodexPetActivitySnapshot(activity: .reviewing, activeSessionIDs: ["session-one"],
            activeScopeCount: 1, activeScopes: [scope])
        let reconciled = try #require(PetTaskSummaryBuilder.reconciling(tasks: [task], snapshot: snapshot).first)

        #expect(reconciled.title == "Fix keyboard navigation")
        #expect(reconciled.status == .waiting)
    }

    @Test("Codex indexed titles and deep links remain unchanged")
    func codexMetadataIsPreserved() throws {
        let thread = CodexThreadSummary(id: "codex-thread", title: "Keep the indexed title", updatedAt: now)
        let task = try #require(PetTaskSummaryBuilder.codexTasks(
            threads: [thread], rolloutsByThreadID: [:], now: now).first)

        #expect(task.title == "Keep the indexed title")
        #expect(task.sourceID == "codex-thread")
        #expect(task.navigationSourceID == "codex-thread")
        #expect(task.deepLinkURL == CodexThreadDeepLink.url(forThreadID: "codex-thread"))
        #expect(task.status == .recent)
    }

    private func event(provider: PetProvider, sessionID: String, kind: String = "tool_started",
                       parentSessionID: String? = nil) -> CodexPetEvent {
        CodexPetEvent(kind: kind, timestamp: 9_995, provider: provider,
            workspace: "/example/shared-project", sessionID: sessionID, parentSessionID: parentSessionID)
    }
}

import Foundation
import Testing
@testable import CodexPetBarCore

@Suite("Attention-first task groups")
struct PetTaskAttentionOrderingTests {
    @Test("an older permission request leads newer running and completed tasks")
    func unresolvedPermissionLeadsRecentWork() {
        let tasks = [
            task("finished", status: .completed, timestamp: 300),
            task("running", status: .running, timestamp: 200),
            task("permission", status: .waiting, timestamp: 100),
        ]

        let groups = PetTaskSummaryGrouping.groups(tasks: tasks)

        #expect(groups.count == 1)
        #expect(groups[0].tasks.map(\.sourceID) == ["permission", "running", "finished"])
    }

    @Test("a project's attention row sets its rank instead of its newest history")
    func projectPriorityUsesStrongestRow() {
        let tasks = [
            task("alpha-new", project: "alpha", status: .completed, timestamp: 900),
            task("alpha-wait", project: "alpha", status: .waiting, timestamp: 100),
            task("beta-failure", project: "beta", status: .failed, timestamp: 200),
            task("beta-old", project: "beta", status: .recent, timestamp: 50),
            task("gamma-running", project: "gamma", status: .running, timestamp: 800),
            task("delta-new", project: "delta", status: .recent, timestamp: 1_000),
        ]

        let groups = PetTaskSummaryGrouping.groups(tasks: tasks)

        #expect(groups.map(\.project.name) == ["beta", "alpha", "gamma", "delta"])
        #expect(groups[0].tasks.map(\.sourceID) == ["beta-failure", "beta-old"])
        #expect(groups[1].tasks.map(\.sourceID) == ["alpha-wait", "alpha-new"])
    }

    @Test("equal-priority equal-time tasks and projects retain input order")
    func tiesAreStable() {
        let tasks = [
            task("beta-first", project: "beta", status: .failed, timestamp: 100),
            task("alpha-first", project: "alpha", status: .waiting, timestamp: 100),
            task("beta-second", project: "beta", status: .waiting, timestamp: 100),
            task("alpha-second", project: "alpha", status: .failed, timestamp: 100),
        ]

        #expect(PetTaskSummaryGrouping.attentionOrdered(tasks).map(\.sourceID) == tasks.map(\.sourceID))
        let groups = PetTaskSummaryGrouping.groups(tasks: tasks)
        #expect(groups.map(\.project.name) == ["beta", "alpha"])
        #expect(groups[0].tasks.map(\.sourceID) == ["beta-first", "beta-second"])
        #expect(groups[1].tasks.map(\.sourceID) == ["alpha-first", "alpha-second"])
    }

    @Test("display limits apply after attention ordering")
    func displayLimitRetainsAttention() {
        let tasks = [
            task("recent", project: "alpha", status: .completed, timestamp: 400),
            task("running", project: "alpha", status: .running, timestamp: 300),
            task("waiting", project: "beta", status: .waiting, timestamp: 100),
            task("failed", project: "gamma", status: .failed, timestamp: 200),
        ]

        let groups = PetTaskSummaryGrouping.groups(tasks: tasks, taskLimit: 2)

        #expect(groups.map(\.project.name) == ["gamma", "beta"])
        #expect(groups.flatMap(\.tasks).map(\.sourceID) == ["failed", "waiting"])
        #expect(PetTaskSummaryGrouping.groups(tasks: tasks, taskLimit: 0).isEmpty)
        #expect(PetTaskSummaryGrouping.groups(tasks: tasks, taskLimit: -1).isEmpty)
    }

    @Test("bounded provider history cannot discard older unresolved attention")
    func providerLimitRetainsAttentionBeforePresentation() {
        let events = [
            CodexPetEvent(kind: "permission_requested", timestamp: 100, provider: .claude,
                          workspace: "/example/waiting", sessionID: "waiting"),
            CodexPetEvent(kind: "tool_failed", timestamp: 200, provider: .cursor,
                          workspace: "/example/failed", sessionID: "failed"),
            CodexPetEvent(kind: "stopped", timestamp: 300, provider: .claude,
                          workspace: "/example/finished", sessionID: "finished"),
            CodexPetEvent(kind: "stopped", timestamp: 350, provider: .cursor,
                          workspace: "/example/newest", sessionID: "newest"),
        ]
        let tasks = PetTaskSummaryBuilder.providerTasks(
            events: events,
            now: Date(timeIntervalSince1970: 400),
            configuration: .init(providerTaskLimit: 1)
        )
        let groups = PetTaskSummaryGrouping.groups(tasks: tasks)

        #expect(groups.flatMap(\.tasks).map(\.sourceID) == ["failed", "waiting", "newest"])
    }

    @Test("resolved attention follows the authoritative snapshot before ordering")
    func staleAttentionDoesNotResurface() {
        let tasks = [
            task("old-wait", status: .waiting, timestamp: 500),
            task("running", status: .running, timestamp: 100),
        ]
        let snapshot = CodexPetActivitySnapshot(
            activity: .running,
            activeSessionIDs: ["running"],
            activeScopeCount: 1,
            activeScopes: [CodexPetActiveScope(provider: .codex, scopedIdentity: "running",
                                                activity: .running, sessionID: "running")]
        )
        let reconciled = PetTaskSummaryBuilder.reconciling(tasks: tasks, snapshot: snapshot)
        let groups = PetTaskSummaryGrouping.groups(tasks: reconciled)

        #expect(groups[0].tasks.map(\.sourceID) == ["running", "old-wait"])
        #expect(groups[0].tasks.map(\.status) == [.running, .recent])
    }

    private func task(
        _ sourceID: String,
        project: String = "example",
        status: PetTaskStatus,
        timestamp: TimeInterval
    ) -> PetTaskSummary {
        PetTaskSummary(sourceID: sourceID, provider: .codex, title: sourceID, detail: "Task detail",
                       status: status, project: .derived(fromWorkspace: "/example/\(project)"),
                       updatedAt: Date(timeIntervalSince1970: timestamp))
    }
}

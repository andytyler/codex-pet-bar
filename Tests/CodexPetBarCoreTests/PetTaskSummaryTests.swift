import Foundation
import Testing
@testable import CodexPetBarCore

@Suite("Pet task summaries")
struct PetTaskSummaryTests {
    @Test("groups projects and tasks by stable recency")
    func groupsProjectsAndTasksByStableRecency() {
        let alpha = PetTaskProject.derived(fromWorkspace: "/Users/example/alpha")
        let beta = PetTaskProject.derived(fromWorkspace: "/Users/example/beta")
        let tasks = [
            task("alpha-old", project: alpha, updatedAt: Date(timeIntervalSince1970: 10)),
            task("beta-new", project: beta, updatedAt: Date(timeIntervalSince1970: 30)),
            task("alpha-new", project: alpha, updatedAt: Date(timeIntervalSince1970: 20)),
            task("beta-tie", project: beta, updatedAt: Date(timeIntervalSince1970: 30)),
        ]

        let groups = PetTaskSummaryGrouping.groups(tasks: tasks)

        #expect(groups.map(\.project.name) == ["beta", "alpha"])
        #expect(groups[0].tasks.map(\.sourceID) == ["beta-new", "beta-tie"])
        #expect(groups[1].tasks.map(\.sourceID) == ["alpha-new", "alpha-old"])
    }

    @Test("derives a stable project without touching the filesystem")
    func derivesProjectFromWorkspace() {
        let project = PetTaskProject.derived(fromWorkspace: "  /Users/example/repos/pet-bar/../pet-bar  ")

        #expect(project.id == "path:/Users/example/repos/pet-bar")
        #expect(project.name == "pet-bar")
        #expect(project.path == "/Users/example/repos/pet-bar")
        #expect(PetTaskProject.derived(fromWorkspace: "  ") == .other)
        #expect(PetTaskProject.derived(fromWorkspace: nil) == .other)
    }

    @Test("missing rollout keeps the indexed Codex task in Other")
    func missingRolloutFallsBackGracefully() throws {
        let fixture = try TaskSummaryFixture()
        let threadID = "019f842c-c312-7332-afec-d21d912578b7"
        try fixture.writeSessionIndex([
            sessionIndexLine(id: threadID, title: "Keep this task", updatedAt: "2026-07-21T10:15:58.668Z"),
        ])

        let tasks = CodexTaskSummaryReader.read(
            sessionIndexURL: fixture.sessionIndexURL,
            sessionsRootURL: fixture.sessionsRootURL,
            now: try date("2026-07-21T10:16:00Z"),
            configuration: .init(recentThreadLimit: 4, adjacentDayRadius: 0)
        )

        let task = try #require(tasks.first)
        #expect(tasks.count == 1)
        #expect(task.sourceID == threadID)
        #expect(task.title == "Keep this task")
        #expect(task.detail == "Recent Codex activity")
        #expect(task.project == .other)
        #expect(task.status == .recent)
        #expect(task.deepLinkURL == CodexThreadDeepLink.url(forThreadID: threadID))
    }

    @Test("finds the UUID rollout in its derived day and uses bounded head and tail metadata")
    func boundedRolloutEnrichment() throws {
        let fixture = try TaskSummaryFixture()
        let threadID = "019f842c-c312-7332-afec-d21d912578b7"
        try fixture.writeSessionIndex([
            sessionIndexLine(id: threadID, title: "Draft judge letters", updatedAt: "not-a-date"),
        ])

        let padding = String(repeating: "x", count: 8_000)
        let sessionMeta = #"{"timestamp":"2026-07-21T10:15:54.419Z","type":"session_meta","payload":{"session_id":"\#(threadID)","cwd":"/Users/example/Repos/openai-codex-ambasador","padding":"\#(padding)"}}"#
        let discarded = #"{"timestamp":"2026-07-21T10:16:00.000Z","type":"event_msg","payload":{"type":"agent_message","message":"\#(padding)"}}"#
        let longDetail = "Finished the letter review " + String(repeating: "carefully ", count: 30)
        let latest = #"{"timestamp":"2026-07-21T10:17:00.000Z","type":"event_msg","payload":{"type":"agent_message","message":"\#(longDetail)","phase":"final_answer"}}"#
        try fixture.writeRollout(
            threadID: threadID,
            day: "2026/07/21",
            lines: [sessionMeta, discarded, latest]
        )

        let tasks = CodexTaskSummaryReader.read(
            sessionIndexURL: fixture.sessionIndexURL,
            sessionsRootURL: fixture.sessionsRootURL,
            now: try date("2026-07-21T10:18:00Z"),
            configuration: .init(
                recentThreadLimit: 4,
                rolloutHeadByteLimit: 256,
                rolloutTailByteLimit: 512,
                adjacentDayRadius: 0
            )
        )

        let task = try #require(tasks.first)
        #expect(task.project.name == "openai-codex-ambasador")
        #expect(task.project.path == "/Users/example/Repos/openai-codex-ambasador")
        #expect(task.detail.hasPrefix("Finished the letter review carefully"))
        #expect(task.detail.count == PetTaskSummary.maximumDetailLength)
        #expect(task.detail.hasSuffix("..."))
        let expectedDate = try date("2026-07-21T10:17:00Z")
        #expect(task.updatedAt == expectedDate)
    }

    @Test("corrupt rollout metadata does not remove its task")
    func corruptRolloutIsNonFatal() throws {
        let fixture = try TaskSummaryFixture()
        let threadID = "019f842c-c312-7332-afec-d21d912578b7"
        try fixture.writeSessionIndex([
            sessionIndexLine(id: threadID, title: "Still visible", updatedAt: "2026-07-21T10:15:58Z"),
        ])
        try fixture.writeRollout(threadID: threadID, day: "2026/07/21", lines: ["not-json", "{broken"])

        let task = try #require(CodexTaskSummaryReader.read(
            sessionIndexURL: fixture.sessionIndexURL,
            sessionsRootURL: fixture.sessionsRootURL,
            configuration: .init(adjacentDayRadius: 0)
        ).first)

        #expect(task.title == "Still visible")
        #expect(task.project == .other)
        #expect(task.detail == "Recent Codex activity")
    }

    @Test("provider identities prevent identical session IDs from colliding")
    func providerSessionsDoNotCollide() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let events = [
            CodexPetEvent(
                kind: "stopped",
                timestamp: 9_990,
                provider: .claude,
                workspace: "/Users/example/alpha",
                sessionID: "same-session",
                assistantSummary: "Implemented the provider adapter and verified the tests"
            ),
            CodexPetEvent(
                kind: "permission_requested",
                timestamp: 9_995,
                provider: .cursor,
                workspace: "/Users/example/beta",
                sessionID: "same-session"
            ),
        ]

        let tasks = PetTaskSummaryBuilder.providerTasks(events: events, now: now)

        #expect(tasks.count == 2)
        #expect(Set(tasks.map(\.id)).count == 2)
        #expect(tasks.map(\.provider) == [.cursor, .claude])
        #expect(tasks.map(\.status) == [.waiting, .completed])
        #expect(tasks.map(\.title) == ["Cursor task", "Claude Code task"])
        #expect(tasks[1].detail == "Implemented the provider adapter and verified the tests")
        #expect(tasks.allSatisfy { !$0.detail.contains("prompt") })
    }

    @Test("child runs keep independent cards but navigate through their real parent session")
    func childRunsNavigateThroughParentSession() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let childID = "parent-thread:subagent:worker-a"
        let event = CodexPetEvent(
            kind: "tool_started",
            timestamp: 9_995,
            provider: .codex,
            workspace: "/Users/example/pet-bar",
            sessionID: childID,
            parentSessionID: "parent-thread"
        )

        let task = try #require(
            PetTaskSummaryBuilder.providerTasks(events: [event], now: now).first
        )

        #expect(task.sourceID == childID)
        #expect(task.navigationSourceID == "parent-thread")
        #expect(task.deepLinkURL == CodexThreadDeepLink.url(forThreadID: "parent-thread"))
        #expect(task.status == .running)
    }

    @Test("provider task project stays pinned when a session changes cwd")
    func providerProjectStaysPinnedAcrossWorkspaceChanges() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let events = [
            CodexPetEvent(
                kind: "session_started",
                timestamp: 9_980,
                provider: .claude,
                workspace: "/Users/example/projects/pet-bar",
                sessionID: "claude-session"
            ),
            CodexPetEvent(
                kind: "stopped",
                timestamp: 9_990,
                provider: .claude,
                workspace: "/Users/example",
                sessionID: "claude-session",
                assistantSummary: "Finished the provider flag work"
            ),
        ]

        let task = try #require(PetTaskSummaryBuilder.providerTasks(events: events, now: now).first)

        #expect(task.project.name == "pet-bar")
        #expect(task.project.path == "/Users/example/projects/pet-bar")
        #expect(task.detail == "Finished the provider flag work")
        #expect(task.status == .completed)
    }

    @Test("hover summaries use the same repaired lifecycle as provider flags")
    func hoverSummariesUseSharedLifecycleReduction() throws {
        let now = Date(timeIntervalSince1970: 200)
        let events = [
            CodexPetEvent(
                kind: "prompt_submitted",
                timestamp: 100,
                provider: .claude,
                sessionID: "claude-session"
            ),
            CodexPetEvent(
                kind: "tool_started",
                timestamp: 110,
                provider: .claude,
                sessionID: "claude-session",
                hookEventName: "Stop"
            ),
            CodexPetEvent(
                kind: "permission_requested",
                timestamp: 170,
                provider: .claude,
                sessionID: "claude-session",
                hookEventName: "Notification"
            ),
            CodexPetEvent(
                kind: "tool_succeeded",
                timestamp: 160,
                provider: .cursor,
                sessionID: "discovered",
                hookEventName: "postToolUse"
            ),
            CodexPetEvent(
                kind: "tool_started",
                timestamp: 190,
                provider: .cursor,
                sessionID: "parent:subagent:opaque",
                parentSessionID: "parent",
                hookEventName: "subagentStart"
            ),
        ]

        let tasks = PetTaskSummaryBuilder.providerTasks(
            events: events,
            now: now,
            configuration: .init(activeStatusWindow: 600)
        )

        #expect(tasks.count == 2)
        let claude = try #require(tasks.first { $0.provider == .claude })
        let cursor = try #require(tasks.first { $0.provider == .cursor })
        #expect(claude.status == .completed)
        #expect(claude.detail == "Finished recently")
        #expect(cursor.sourceID == "discovered")
        #expect(cursor.status == .recent)
        #expect(cursor.detail == "Recent Cursor activity")
        #expect(!tasks.contains { $0.sourceID == "parent:subagent:opaque" })
    }

    @Test("hover summaries match flags for actionable notifications and terminal turn latching")
    func hoverAndFlagLifecycleParityAcrossTerminalBoundary() throws {
        let completedEvents = [
            CodexPetEvent(
                kind: "prompt_submitted",
                timestamp: 100,
                provider: .claude,
                sessionID: "claude-session",
                turnID: "turn-a"
            ),
            CodexPetEvent(
                kind: "permission_requested",
                timestamp: 105,
                provider: .claude,
                sessionID: "claude-session",
                turnID: "turn-a",
                hookEventName: "Notification",
                status: "permission_prompt"
            ),
            CodexPetEvent(
                kind: "stopped",
                timestamp: 110,
                provider: .claude,
                sessionID: "claude-session",
                turnID: "turn-a",
                hookEventName: "Stop",
                assistantSummary: "Finished the first turn"
            ),
            CodexPetEvent(
                kind: "permission_requested",
                timestamp: 111,
                provider: .claude,
                sessionID: "claude-session",
                turnID: "turn-a",
                hookEventName: "PermissionRequest"
            ),
            CodexPetEvent(
                kind: "tool_failed",
                timestamp: 112,
                provider: .claude,
                sessionID: "claude-session",
                turnID: "turn-a",
                hookEventName: "PostToolUseFailure"
            ),
        ]

        let beforeStopFlags = CodexPetEventLog.snapshot(
            events: Array(completedEvents.prefix(2)),
            now: Date(timeIntervalSince1970: 106)
        )
        let beforeStopCard = try #require(PetTaskSummaryBuilder.providerTasks(
            events: Array(completedEvents.prefix(2)),
            now: Date(timeIntervalSince1970: 106)
        ).first)
        let completedFlags = CodexPetEventLog.snapshot(
            events: completedEvents,
            now: Date(timeIntervalSince1970: 113)
        )
        let completedCard = try #require(PetTaskSummaryBuilder.providerTasks(
            events: completedEvents,
            now: Date(timeIntervalSince1970: 113)
        ).first)

        #expect(beforeStopFlags.activity == .reviewing)
        #expect(beforeStopCard.status == .waiting)
        #expect(beforeStopCard.detail == "Waiting for permission")
        #expect(completedFlags.activity == .idle)
        #expect(completedFlags.activeScopes.isEmpty)
        #expect(completedCard.status == .completed)
        #expect(completedCard.detail == "Finished the first turn")
        #expect(completedCard.updatedAt == Date(timeIntervalSince1970: 110))
    }

    @Test("tool completion discovery grace matches flags and hover status")
    func toolCompletionDiscoveryGraceMatchesAcrossSurfaces() throws {
        let event = CodexPetEvent(
            kind: "tool_succeeded",
            timestamp: 100,
            provider: .cursor,
            sessionID: "cursor-session",
            hookEventName: "postToolUse"
        )

        let duringGrace = try #require(PetTaskSummaryBuilder.providerTasks(
            events: [event],
            now: Date(timeIntervalSince1970: 130),
            configuration: .init(activeStatusWindow: 600)
        ).first)
        let afterGrace = try #require(PetTaskSummaryBuilder.providerTasks(
            events: [event],
            now: Date(timeIntervalSince1970: 131),
            configuration: .init(activeStatusWindow: 600)
        ).first)

        #expect(duringGrace.status == .running)
        #expect(duringGrace.detail == "Working")
        #expect(afterGrace.status == .recent)
        #expect(afterGrace.detail == "Recent Cursor activity")
    }

    @Test("Codex status events are merged without replacing rollout summaries")
    func codexStatusOverlayRetainsAssistantDetail() throws {
        let threadID = "019f842c-c312-7332-afec-d21d912578b7"
        let now = Date(timeIntervalSince1970: 10_000)
        let thread = CodexThreadSummary(
            id: threadID,
            title: "Review app",
            updatedAt: Date(timeIntervalSince1970: 9_900)
        )
        let rollout = CodexRolloutTaskMetadata(
            threadID: threadID,
            workspace: "/Users/example/pet-bar",
            latestDetail: "Optimized animation decoding",
            latestMessageDate: Date(timeIntervalSince1970: 9_950)
        )
        let event = CodexPetEvent(
            kind: "tool_failed",
            timestamp: 9_990,
            provider: .codex,
            workspace: "/wrong/fallback",
            sessionID: threadID
        )

        let task = try #require(PetTaskSummaryBuilder.codexTasks(
            threads: [thread],
            rolloutsByThreadID: [threadID: rollout],
            providerEvents: [event],
            now: now
        ).first)

        #expect(task.detail == "Optimized animation decoding")
        #expect(task.status == .failed)
        #expect(task.project.name == "pet-bar")
        #expect(task.updatedAt == Date(timeIntervalSince1970: 9_990))
    }

    @Test("a newer terminal event summary supersedes an older rollout detail")
    func newerTerminalSummaryWins() throws {
        let threadID = "019f842c-c312-7332-afec-d21d912578b7"
        let now = Date(timeIntervalSince1970: 10_000)
        let thread = CodexThreadSummary(
            id: threadID,
            title: "Review app",
            updatedAt: Date(timeIntervalSince1970: 9_900)
        )
        let rollout = CodexRolloutTaskMetadata(
            threadID: threadID,
            workspace: "/Users/example/pet-bar",
            latestDetail: "Older rollout detail",
            latestMessageDate: Date(timeIntervalSince1970: 9_950)
        )
        let events = [
            CodexPetEvent(
                kind: "stopped",
                timestamp: 9_990,
                provider: .codex,
                workspace: "/Users/example/pet-bar",
                sessionID: threadID,
                turnID: "turn-a",
                assistantSummary: "Shipped the hover cards and verified the app"
            ),
            CodexPetEvent(
                kind: "stopped",
                timestamp: 9_991,
                provider: .codex,
                workspace: "/Users/example/pet-bar",
                sessionID: threadID,
                turnID: "turn-a"
            ),
        ]

        let task = try #require(PetTaskSummaryBuilder.codexTasks(
            threads: [thread],
            rolloutsByThreadID: [threadID: rollout],
            providerEvents: events,
            now: now
        ).first)

        #expect(task.detail == "Shipped the hover cards and verified the app")
        #expect(task.status == .completed)
        #expect(task.updatedAt == Date(timeIntervalSince1970: 9_991))
    }

    @Test("Cursor keeps the newest same-turn summary when stop arrives afterward")
    func cursorSummarySurvivesNewerStop() throws {
        let now = Date(timeIntervalSince1970: 110)
        let events = [
            CodexPetEvent(
                kind: "stopped",
                timestamp: 99,
                provider: .cursor,
                sessionID: "cursor-session",
                turnID: "generation-a",
                hookEventName: "afterAgentResponse",
                assistantSummary: "Older safe summary"
            ),
            CodexPetEvent(
                kind: "stopped",
                timestamp: 100,
                provider: .cursor,
                sessionID: "cursor-session",
                turnID: "generation-a",
                hookEventName: "afterAgentResponse",
                assistantSummary: "Finished the Cursor change and verified it"
            ),
            CodexPetEvent(
                kind: "stopped",
                timestamp: 101,
                provider: .cursor,
                sessionID: "cursor-session",
                turnID: "generation-a",
                hookEventName: "stop"
            ),
        ]

        let task = try #require(PetTaskSummaryBuilder.providerTasks(events: events, now: now).first)

        #expect(task.detail == "Finished the Cursor change and verified it")
        #expect(task.status == .completed)
        #expect(task.updatedAt == Date(timeIntervalSince1970: 101))
    }

    @Test("terminal state remains authoritative over a delayed same-turn failure")
    func terminalStateIgnoresDelayedSameTurnFailure() throws {
        let events = [
            CodexPetEvent(
                kind: "stopped",
                timestamp: 100,
                provider: .cursor,
                sessionID: "cursor-session",
                turnID: "generation-a",
                assistantSummary: "Completed most of the work"
            ),
            CodexPetEvent(
                kind: "tool_failed",
                timestamp: 101,
                provider: .cursor,
                sessionID: "cursor-session",
                turnID: "generation-a"
            ),
        ]

        let task = try #require(PetTaskSummaryBuilder.providerTasks(
            events: events,
            now: Date(timeIntervalSince1970: 102)
        ).first)

        #expect(task.detail == "Completed most of the work")
        #expect(task.status == .completed)
        #expect(task.updatedAt == Date(timeIntervalSince1970: 100))
    }

    @Test("tight timestamp fallback retains terminal summaries but never crosses new work")
    func terminalSummaryTimestampFallbackIsTurnSafe() throws {
        let safeEvents = [
            CodexPetEvent(
                kind: "stopped",
                timestamp: 100,
                provider: .cursor,
                sessionID: "safe",
                assistantSummary: "Safe fallback summary"
            ),
            CodexPetEvent(
                kind: "stopped",
                timestamp: 104,
                provider: .cursor,
                sessionID: "safe"
            ),
        ]
        let crossedTurnEvents = [
            CodexPetEvent(
                kind: "stopped",
                timestamp: 100,
                provider: .cursor,
                sessionID: "crossed",
                assistantSummary: "Must not leak"
            ),
            CodexPetEvent(
                kind: "prompt_submitted",
                timestamp: 102,
                provider: .cursor,
                sessionID: "crossed"
            ),
            CodexPetEvent(
                kind: "stopped",
                timestamp: 103,
                provider: .cursor,
                sessionID: "crossed"
            ),
        ]
        let expiredEvents = [
            CodexPetEvent(
                kind: "stopped",
                timestamp: 100,
                provider: .cursor,
                sessionID: "expired",
                assistantSummary: "Also must not leak"
            ),
            CodexPetEvent(
                kind: "stopped",
                timestamp: 106,
                provider: .cursor,
                sessionID: "expired"
            ),
        ]
        let laterRunEvents = [
            CodexPetEvent(
                kind: "stopped",
                timestamp: 100,
                provider: .cursor,
                sessionID: "later-run",
                assistantSummary: "Prior run summary"
            ),
            CodexPetEvent(
                kind: "prompt_submitted",
                timestamp: 101,
                provider: .cursor,
                sessionID: "later-run"
            ),
            CodexPetEvent(
                kind: "tool_started",
                timestamp: 102,
                provider: .cursor,
                sessionID: "later-run"
            ),
        ]

        let tasks = PetTaskSummaryBuilder.providerTasks(
            events: safeEvents + crossedTurnEvents + expiredEvents + laterRunEvents,
            now: Date(timeIntervalSince1970: 110)
        )
        let details = Dictionary(uniqueKeysWithValues: tasks.map { ($0.sourceID, $0.detail) })

        #expect(details["safe"] == "Safe fallback summary")
        #expect(details["crossed"] == "Finished recently")
        #expect(details["expired"] == "Finished recently")
        #expect(details["later-run"] == "Working")
    }

    @Test("different explicit turn IDs prevent prior summaries on provider and Codex cards")
    func explicitTurnIDsPreventSummaryLeakage() throws {
        let threadID = "019f842c-c312-7332-afec-d21d912578b7"
        let events = [
            CodexPetEvent(
                kind: "stopped",
                timestamp: 100,
                provider: .codex,
                sessionID: threadID,
                turnID: "old-turn",
                assistantSummary: "Old turn summary"
            ),
            CodexPetEvent(
                kind: "tool_started",
                timestamp: 101,
                provider: .codex,
                sessionID: threadID,
                turnID: "new-turn"
            ),
        ]
        let rollout = CodexRolloutTaskMetadata(
            threadID: threadID,
            workspace: "/Users/example/pet-bar",
            latestDetail: "Current rollout detail",
            latestMessageDate: Date(timeIntervalSince1970: 100.5)
        )
        let thread = CodexThreadSummary(
            id: threadID,
            title: "Review app",
            updatedAt: Date(timeIntervalSince1970: 99)
        )

        let providerTask = try #require(PetTaskSummaryBuilder.providerTasks(
            events: events,
            now: Date(timeIntervalSince1970: 102)
        ).first)
        let codexTask = try #require(PetTaskSummaryBuilder.codexTasks(
            threads: [thread],
            rolloutsByThreadID: [threadID: rollout],
            providerEvents: events,
            now: Date(timeIntervalSince1970: 102)
        ).first)

        #expect(providerTask.detail == "Working")
        #expect(providerTask.status == .running)
        #expect(codexTask.detail == "Current rollout detail")
        #expect(codexTask.status == .running)
        #expect(!providerTask.detail.contains("Old turn"))
        #expect(!codexTask.detail.contains("Old turn"))
    }

    @Test("attention sessions bypass inactive provider history limits")
    func attentionSessionsSurviveProviderLimits() {
        let now = Date(timeIntervalSince1970: 10_000)
        let events = [
            CodexPetEvent(
                kind: "tool_started",
                timestamp: 9_990,
                provider: .claude,
                workspace: "/Users/example/alpha",
                sessionID: "running"
            ),
            CodexPetEvent(
                kind: "permission_requested",
                timestamp: 9_980,
                provider: .cursor,
                workspace: "/Users/example/beta",
                sessionID: "waiting"
            ),
            CodexPetEvent(
                kind: "tool_failed",
                timestamp: 9_970,
                provider: .claude,
                workspace: "/Users/example/gamma",
                sessionID: "failed"
            ),
            CodexPetEvent(
                kind: "stopped",
                timestamp: 9_999,
                provider: .cursor,
                workspace: "/Users/example/delta",
                sessionID: "newest-history"
            ),
            CodexPetEvent(
                kind: "stopped",
                timestamp: 9_998,
                provider: .claude,
                workspace: "/Users/example/epsilon",
                sessionID: "overflow-history"
            ),
        ]
        let configuration = PetTaskSummaryConfiguration(
            providerTaskLimit: 1,
            providerEventRecentWindow: 2
        )

        let tasks = PetTaskSummaryBuilder.providerTasks(
            events: events,
            excluding: [.codex],
            now: now,
            configuration: configuration
        )

        #expect(tasks.map(\.sourceID) == ["newest-history", "running", "waiting", "failed"])
        #expect(tasks.map(\.status) == [.completed, .running, .waiting, .failed])

        var zeroHistoryConfiguration = configuration
        zeroHistoryConfiguration.providerTaskLimit = 0
        let activeOnly = PetTaskSummaryBuilder.providerTasks(
            events: events,
            excluding: [.codex],
            now: now,
            configuration: zeroHistoryConfiguration
        )
        #expect(activeOnly.map(\.sourceID) == ["running", "waiting", "failed"])
    }

    @Test("quiet hook-only running work expires while attention remains")
    func lifecycleGraceWindowsMatchTheActivitySurface() {
        let now = Date(timeIntervalSince1970: 100_000)
        let twoHoursAgo = now.timeIntervalSince1970 - (2 * 60 * 60)
        let events = [
            CodexPetEvent(
                kind: "tool_started",
                timestamp: twoHoursAgo,
                provider: .claude,
                sessionID: "long-tool"
            ),
            CodexPetEvent(
                kind: "permission_requested",
                timestamp: twoHoursAgo,
                provider: .cursor,
                sessionID: "waiting"
            ),
            CodexPetEvent(
                kind: "session_started",
                timestamp: twoHoursAgo,
                provider: .claude,
                sessionID: "idle-session"
            ),
        ]
        var configuration = PetTaskSummaryConfiguration()
        configuration.providerTaskLimit = 0
        configuration.providerEventRecentWindow = 0

        let tasks = PetTaskSummaryBuilder.providerTasks(
            events: events,
            excluding: [.codex],
            now: now,
            configuration: configuration
        )

        #expect(tasks.map(\.sourceID) == ["waiting"])
        #expect(tasks.map(\.status) == [.waiting])
    }

    @Test("thirty-minute hook-only lease matches flag and hover status boundaries")
    func hookOnlyRunningLeaseMatchesAcrossSurfaces() throws {
        let events = [
            CodexPetEvent(
                kind: "tool_started",
                timestamp: 100,
                provider: .codex,
                sessionID: "codex-running"
            ),
            CodexPetEvent(
                kind: "tool_started",
                timestamp: 100,
                provider: .claude,
                sessionID: "claude-running"
            ),
            CodexPetEvent(
                kind: "tool_started",
                timestamp: 100,
                provider: .cursor,
                sessionID: "cursor-running"
            ),
            CodexPetEvent(
                kind: "permission_requested",
                timestamp: 100,
                provider: .claude,
                sessionID: "claude-waiting"
            ),
        ]

        let atTwentyNineMinutes = Date(timeIntervalSince1970: 100 + (29 * 60))
        let atThirtyOneMinutes = Date(timeIntervalSince1970: 100 + (31 * 60))
        let flagsAtTwentyNine = CodexPetEventLog.snapshot(events: events, now: atTwentyNineMinutes)
        let flagsAtThirtyOne = CodexPetEventLog.snapshot(events: events, now: atThirtyOneMinutes)
        let cardsAtTwentyNine = PetTaskSummaryBuilder.providerTasks(
            events: events,
            now: atTwentyNineMinutes
        )
        let cardsAtThirtyOne = PetTaskSummaryBuilder.providerTasks(
            events: events,
            now: atThirtyOneMinutes
        )
        let statusAtTwentyNine = Dictionary(
            uniqueKeysWithValues: cardsAtTwentyNine.map { ($0.sourceID, $0.status) }
        )
        let statusAtThirtyOne = Dictionary(
            uniqueKeysWithValues: cardsAtThirtyOne.map { ($0.sourceID, $0.status) }
        )

        #expect(flagsAtTwentyNine.activeScopeCount == 4)
        #expect(statusAtTwentyNine["codex-running"] == .running)
        #expect(statusAtTwentyNine["claude-running"] == .running)
        #expect(statusAtTwentyNine["cursor-running"] == .running)
        #expect(statusAtTwentyNine["claude-waiting"] == .waiting)
        #expect(flagsAtThirtyOne.activeSessionIDs == [
            "codex-running",
            "claude:claude-waiting",
        ])
        #expect(statusAtThirtyOne["codex-running"] == .running)
        #expect(statusAtThirtyOne["claude-running"] == .recent)
        #expect(statusAtThirtyOne["cursor-running"] == .recent)
        #expect(statusAtThirtyOne["claude-waiting"] == .waiting)
    }

    @Test("an active Codex hook session outside the bounded index is synthesized")
    func unindexedActiveCodexSessionIsSynthesized() throws {
        let fixture = try TaskSummaryFixture()
        let indexedLines = (0..<18).map { index in
            sessionIndexLine(
                id: "indexed-\(index)",
                title: "Indexed task \(index)",
                updatedAt: String(format: "2026-07-21T10:15:%02dZ", index)
            )
        }
        try fixture.writeSessionIndex(indexedLines)
        let now = try date("2026-07-21T10:16:00Z")
        let activeEvent = CodexPetEvent(
            kind: "tool_started",
            timestamp: now.timeIntervalSince1970 - 5,
            provider: .codex,
            workspace: "/Users/example/projects/outside-index",
            sessionID: "active-outside-index"
        )

        let tasks = CodexTaskSummaryReader.read(
            sessionIndexURL: fixture.sessionIndexURL,
            sessionsRootURL: fixture.sessionsRootURL,
            providerEvents: [activeEvent],
            now: now,
            configuration: .init(
                recentThreadLimit: 18,
                providerTaskLimit: 0,
                providerEventRecentWindow: 0
            )
        )

        let synthetic = try #require(tasks.first { $0.sourceID == "active-outside-index" })
        #expect(tasks.count == 19)
        #expect(synthetic.id == "codex:active-outside-index")
        #expect(synthetic.title == "Codex task")
        #expect(synthetic.detail == "Working")
        #expect(synthetic.status == .running)
        #expect(synthetic.project.name == "outside-index")
        #expect(synthetic.deepLinkURL == CodexThreadDeepLink.url(forThreadID: "active-outside-index"))
    }

    @Test("an indexed active Codex session is not duplicated")
    func indexedActiveCodexSessionIsNotDuplicated() throws {
        let fixture = try TaskSummaryFixture()
        let threadID = "019f842c-c312-7332-afec-d21d912578b7"
        try fixture.writeSessionIndex([
            sessionIndexLine(id: threadID, title: "Indexed active task", updatedAt: "2026-07-21T10:15:58Z"),
        ])
        let now = try date("2026-07-21T10:16:00Z")
        let activeEvent = CodexPetEvent(
            kind: "permission_requested",
            timestamp: now.timeIntervalSince1970 - 1,
            provider: .codex,
            workspace: "/Users/example/projects/pet-bar",
            sessionID: threadID
        )

        let tasks = CodexTaskSummaryReader.read(
            sessionIndexURL: fixture.sessionIndexURL,
            sessionsRootURL: fixture.sessionsRootURL,
            providerEvents: [activeEvent],
            now: now
        )

        #expect(tasks.count == 1)
        #expect(tasks[0].sourceID == threadID)
        #expect(tasks[0].title == "Indexed active task")
        #expect(tasks[0].status == .waiting)
        #expect(tasks[0].project.name == "pet-bar")
    }

    @Test("bounded file reads never exceed configured bytes and omit partial lines")
    func boundedReadsAreActuallyBounded() throws {
        let fixture = try TaskSummaryFixture()
        let file = fixture.rootURL.appendingPathComponent("bounded.jsonl")
        try (String(repeating: "a", count: 100) + "\ncomplete\npartial")
            .write(to: file, atomically: true, encoding: .utf8)

        let head = try BoundedTaskFileReader.headData(from: file, byteLimit: 16)
        let tail = try BoundedTaskFileReader.tailCompleteLineData(from: file, byteLimit: 24)

        #expect(head.count == 16)
        #expect(tail.count <= 24)
        #expect(String(decoding: tail, as: UTF8.self) == "complete\n")
    }

    private func task(_ sourceID: String, project: PetTaskProject, updatedAt: Date) -> PetTaskSummary {
        PetTaskSummary(
            sourceID: sourceID,
            provider: .codex,
            title: sourceID,
            detail: "detail",
            status: .recent,
            project: project,
            updatedAt: updatedAt
        )
    }
}

private struct TaskSummaryFixture {
    let rootURL: URL
    let sessionIndexURL: URL
    let sessionsRootURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PetTaskSummaryTests-\(UUID().uuidString)", isDirectory: true)
        sessionIndexURL = rootURL.appendingPathComponent("session_index.jsonl")
        sessionsRootURL = rootURL.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsRootURL, withIntermediateDirectories: true)
    }

    func writeSessionIndex(_ lines: [String]) throws {
        try (lines.joined(separator: "\n") + "\n")
            .write(to: sessionIndexURL, atomically: true, encoding: .utf8)
    }

    func writeRollout(threadID: String, day: String, lines: [String]) throws {
        let directory = sessionsRootURL.appendingPathComponent(day, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("rollout-2026-07-21T10-15-53-\(threadID).jsonl")
        try (lines.joined(separator: "\n") + "\n")
            .write(to: file, atomically: true, encoding: .utf8)
    }
}

private func sessionIndexLine(id: String, title: String, updatedAt: String) -> String {
    #"{"id":"\#(id)","thread_name":"\#(title)","updated_at":"\#(updatedAt)"}"#
}

private func date(_ value: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: value))
}

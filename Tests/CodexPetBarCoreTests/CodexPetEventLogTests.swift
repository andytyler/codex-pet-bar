import Foundation
import Testing
@testable import CodexPetBarCore

@Suite("Codex pet event log")
struct CodexPetEventLogTests {
    @Test("provider metadata and bounded summaries decode while legacy events remain Codex")
    func providerMetadataDecodesWithCodexFallback() throws {
        let legacy = try #require(
            CodexPetEvent(
                jsonLine: #"{"event":"tool_started","timestamp":100,"session_id":"shared"}"#
            )
        )
        let claude = try #require(
            CodexPetEvent(
                jsonLine: #"{"event":"stopped","timestamp":101,"provider":"claude","session_id":"shared:subagent:child","parent_session_id":"shared","assistant_summary":"Finished the refactor","status":"completed"}"#
            )
        )

        #expect(legacy.provider == .codex)
        #expect(legacy.assistantSummary == nil)
        #expect(claude.provider == .claude)
        #expect(claude.parentSessionID == "shared")
        #expect(claude.assistantSummary == "Finished the refactor")
        #expect(claude.status == "completed")
    }

    @Test("same workspace and session IDs remain independent across providers")
    func providerScopesDoNotCollide() {
        let log = """
        {"event":"tool_started","timestamp":100,"provider":"codex","workspace":"/workspace","session_id":"shared"}
        {"event":"tool_started","timestamp":101,"provider":"claude","workspace":"/workspace","session_id":"shared"}
        {"event":"stopped","timestamp":102,"provider":"cursor","workspace":"/workspace","session_id":"shared"}
        """

        let snapshot = CodexPetEventLog.snapshot(
            jsonLines: log,
            now: Date(timeIntervalSince1970: 105),
            activeWindow: 30
        )

        #expect(snapshot.activity == .running)
        #expect(snapshot.activeScopeCount == 2)
        #expect(snapshot.activeSessionIDs == ["shared", "claude:shared"])
        #expect(snapshot.activeScopes.map(\.provider) == [.codex, .claude])
        #expect(snapshot.activeScopes.map(\.activity) == [.running, .running])
        #expect(Set(snapshot.activeScopes.map(\.scopedIdentity)).count == 2)
    }

    @Test("mixed providers and multiple same-provider sessions remain separate and deterministically ordered")
    func mixedProviderScopesAreSeparateAndOrdered() {
        let log = """
        {"event":"tool_started","timestamp":105,"provider":"cursor","workspace":"/workspace","session_id":"cursor-b"}
        {"event":"tool_started","timestamp":104,"provider":"claude","workspace":"/workspace","session_id":"claude-b"}
        {"event":"tool_started","timestamp":103,"provider":"codex","workspace":"/workspace","session_id":"codex-b"}
        {"event":"tool_started","timestamp":102,"provider":"cursor","workspace":"/workspace","session_id":"cursor-a"}
        {"event":"tool_started","timestamp":101,"provider":"claude","workspace":"/workspace","session_id":"claude-a"}
        {"event":"tool_started","timestamp":100,"provider":"codex","workspace":"/workspace","session_id":"codex-a"}
        """

        let snapshot = CodexPetEventLog.snapshot(
            jsonLines: log,
            now: Date(timeIntervalSince1970: 110),
            activeWindow: 30
        )

        #expect(snapshot.activeScopeCount == 6)
        #expect(snapshot.activeScopes.map(\.provider) == [.codex, .codex, .claude, .claude, .cursor, .cursor])
        #expect(snapshot.activeScopes.map(\.activity) == Array(repeating: .running, count: 6))
        #expect(Set(snapshot.activeScopes.map(\.scopedIdentity)).count == 6)
        #expect(
            snapshot.activeSessionIDs == [
                "codex-a", "codex-b",
                "claude:claude-a", "claude:claude-b",
                "cursor:cursor-a", "cursor:cursor-b",
            ]
        )

        let reversed = CodexPetEventLog.snapshot(
            jsonLines: log.split(separator: "\n").reversed().joined(separator: "\n"),
            now: Date(timeIntervalSince1970: 110),
            activeWindow: 30
        )
        #expect(reversed.activeScopes == snapshot.activeScopes)
    }

    @Test("scope identity is stable across activity changes and uses turn ID when a session is unavailable")
    func scopeIdentityIsStable() throws {
        let sessionStarted = CodexPetEventLog.snapshot(
            jsonLines: #"{"event":"session_started","timestamp":100,"provider":"claude","workspace":"/workspace","session_id":"session-a","turn_id":"turn-a"}"#,
            now: Date(timeIntervalSince1970: 101)
        )
        let sessionRunning = CodexPetEventLog.snapshot(
            jsonLines: #"{"event":"tool_started","timestamp":102,"provider":"claude","workspace":"/workspace","session_id":"session-a","turn_id":"turn-b"}"#,
            now: Date(timeIntervalSince1970: 103)
        )
        let turnA = CodexPetEventLog.snapshot(
            jsonLines: #"{"event":"tool_started","timestamp":104,"provider":"cursor","workspace":"/workspace","turn_id":"turn-a"}"#,
            now: Date(timeIntervalSince1970: 105)
        )
        let turnB = CodexPetEventLog.snapshot(
            jsonLines: #"{"event":"tool_started","timestamp":104,"provider":"cursor","workspace":"/workspace","turn_id":"turn-b"}"#,
            now: Date(timeIntervalSince1970: 105)
        )

        let startedScope = try #require(sessionStarted.activeScopes.first)
        let runningScope = try #require(sessionRunning.activeScopes.first)
        let turnAScope = try #require(turnA.activeScopes.first)
        let turnBScope = try #require(turnB.activeScopes.first)

        #expect(startedScope.scopedIdentity == runningScope.scopedIdentity)
        #expect(startedScope.id == startedScope.scopedIdentity)
        #expect(startedScope.activity == .listening)
        #expect(runningScope.activity == .running)
        #expect(turnAScope.scopedIdentity != turnBScope.scopedIdentity)
    }

    @Test("session identity survives provider cwd changes without phantom flags")
    func sessionIdentitySurvivesWorkspaceChanges() {
        let completed = CodexPetEventLog.snapshot(
            jsonLines: """
            {"event":"tool_started","timestamp":100,"provider":"claude","workspace":"/workspace/project","session_id":"claude-session"}
            {"event":"stopped","timestamp":101,"provider":"claude","workspace":"/workspace","session_id":"claude-session"}
            """,
            now: Date(timeIntervalSince1970: 102),
            activeWindow: 30
        )
        let stillRunning = CodexPetEventLog.snapshot(
            jsonLines: """
            {"event":"tool_started","timestamp":100,"provider":"claude","workspace":"/workspace/project","session_id":"claude-session"}
            {"event":"tool_succeeded","timestamp":101,"provider":"claude","workspace":"/workspace","session_id":"claude-session"}
            """,
            now: Date(timeIntervalSince1970: 102),
            activeWindow: 30
        )

        #expect(completed.activeScopes.isEmpty)
        #expect(completed.activeSessionIDs.isEmpty)
        #expect(stillRunning.activeScopes.count == 1)
        #expect(stillRunning.activeScopes.first?.provider == .claude)
        #expect(stillRunning.activeSessionIDs == ["claude:claude-session"])
    }

    @Test("activity snapshot reports active hook sessions")
    func activitySnapshotReportsActiveHookSessions() {
        let log = """
        {"event":"tool_started","timestamp":100,"workspace":"/workspace-a","session_id":"thread-a"}
        {"event":"permission_requested","timestamp":101,"workspace":"/workspace-b","session_id":"thread-b"}
        {"event":"stopped","timestamp":102,"workspace":"/workspace-c","session_id":"thread-c"}
        """

        let snapshot = CodexPetEventLog.snapshot(
            jsonLines: log,
            now: Date(timeIntervalSince1970: 105),
            activeWindow: 30
        )

        #expect(snapshot.activity == .reviewing)
        #expect(snapshot.activeScopeCount == 2)
        #expect(snapshot.activeSessionIDs == ["thread-a", "thread-b"])
    }

    @Test("unresolved permission requests eventually expire")
    func unresolvedPermissionRequestsEventuallyExpire() {
        let log = """
        {"event":"permission_requested","timestamp":100,"workspace":"/workspace-a","session_id":"thread-a"}
        """

        let snapshot = CodexPetEventLog.snapshot(
            jsonLines: log,
            now: Date(timeIntervalSince1970: 2_000),
            activeWindow: 30,
            reviewWindow: 900
        )

        #expect(snapshot.activity == nil)
        #expect(snapshot.activeScopeCount == 0)
        #expect(snapshot.activeSessionIDs.isEmpty)
    }

    @Test("hook-only running work expires while attention remains active")
    func hookOnlyRunningWorkUsesProviderLease() {
        let log = """
        {"event":"tool_started","timestamp":100,"provider":"claude","session_id":"long-tool"}
        {"event":"session_started","timestamp":100,"provider":"cursor","session_id":"idle-session"}
        {"event":"permission_requested","timestamp":100,"provider":"codex","session_id":"waiting"}
        """

        let afterTwoHours = CodexPetEventLog.snapshot(
            jsonLines: log,
            now: Date(timeIntervalSince1970: 100 + (2 * 60 * 60))
        )
        let afterSevenHours = CodexPetEventLog.snapshot(
            jsonLines: log,
            now: Date(timeIntervalSince1970: 100 + (7 * 60 * 60)),
            reviewWindow: 24 * 60 * 60
        )

        #expect(afterTwoHours.activeScopes.map(\.provider) == [.codex])
        #expect(afterTwoHours.activeScopes.map(\.activity) == [.reviewing])
        #expect(!afterTwoHours.activeSessionIDs.contains("claude:long-tool"))
        #expect(!afterTwoHours.activeSessionIDs.contains("cursor:idle-session"))
        #expect(afterSevenHours.activeScopes.map(\.provider) == [.codex])
        #expect(afterSevenHours.activeScopes.first?.activity == .reviewing)
    }

    @Test("Claude and Cursor running leases expire after thirty minutes without shortening attention")
    func hookOnlyProviderRunningLeaseBoundaries() {
        let log = """
        {"event":"tool_started","timestamp":100,"provider":"codex","session_id":"codex-running"}
        {"event":"tool_started","timestamp":100,"provider":"claude","session_id":"claude-running"}
        {"event":"tool_started","timestamp":100,"provider":"cursor","session_id":"cursor-running"}
        {"event":"permission_requested","timestamp":100,"provider":"claude","session_id":"claude-waiting"}
        """

        let afterTwentyNineMinutes = CodexPetEventLog.snapshot(
            jsonLines: log,
            now: Date(timeIntervalSince1970: 100 + (29 * 60))
        )
        let afterThirtyOneMinutes = CodexPetEventLog.snapshot(
            jsonLines: log,
            now: Date(timeIntervalSince1970: 100 + (31 * 60))
        )
        let shorterConfiguredWindow = CodexPetEventLog.snapshot(
            jsonLines: log,
            now: Date(timeIntervalSince1970: 100 + (21 * 60)),
            activeWindow: 20 * 60
        )

        #expect(afterTwentyNineMinutes.activeSessionIDs == [
            "codex-running",
            "claude:claude-running",
            "claude:claude-waiting",
            "cursor:cursor-running",
        ])
        #expect(afterThirtyOneMinutes.activeSessionIDs == [
            "codex-running",
            "claude:claude-waiting",
        ])
        #expect(afterThirtyOneMinutes.activeScopes.map(\.activity) == [.running, .reviewing])
        #expect(shorterConfiguredWindow.activeSessionIDs == ["claude:claude-waiting"])
        #expect(shorterConfiguredWindow.activeScopes.first?.activity == .reviewing)
    }

    @Test("permission attention uses the longer review window independently for each scope")
    func permissionAttentionUsesLongerWindowPerScope() {
        let log = """
        {"event":"permission_requested","timestamp":100,"provider":"claude","workspace":"/workspace","session_id":"waiting"}
        {"event":"tool_started","timestamp":100,"provider":"cursor","workspace":"/workspace","session_id":"stale-running"}
        {"event":"tool_started","timestamp":280,"provider":"codex","workspace":"/workspace","session_id":"live-running"}
        """

        let snapshot = CodexPetEventLog.snapshot(
            jsonLines: log,
            now: Date(timeIntervalSince1970: 300),
            activeWindow: 30
        )

        #expect(snapshot.activity == .reviewing)
        #expect(snapshot.activeScopeCount == 2)
        #expect(snapshot.activeScopes.map(\.provider) == [.codex, .claude])
        #expect(snapshot.activeScopes.map(\.activity) == [.running, .reviewing])
        #expect(snapshot.activeSessionIDs == ["live-running", "claude:waiting"])
    }

    @Test("unknown event kinds neither create scopes nor mask pending attention")
    func unknownKindsAreIgnored() {
        let unknownOnly = CodexPetEventLog.snapshot(
            jsonLines: #"{"event":"future_event","timestamp":500,"provider":"cursor","workspace":"/workspace","session_id":"unknown"}"#,
            now: Date(timeIntervalSince1970: 505),
            activeWindow: 30
        )
        let afterPermission = CodexPetEventLog.snapshot(
            jsonLines: """
            {"event":"permission_requested","timestamp":100,"provider":"claude","workspace":"/workspace","session_id":"waiting"}
            {"event":"future_event","timestamp":500,"provider":"claude","workspace":"/workspace","session_id":"waiting"}
            """,
            now: Date(timeIntervalSince1970: 505),
            activeWindow: 30,
            reviewWindow: 900
        )

        #expect(unknownOnly.activity == nil)
        #expect(unknownOnly.activeScopeCount == 0)
        #expect(unknownOnly.activeScopes.isEmpty)
        #expect(unknownOnly.activeSessionIDs.isEmpty)
        #expect(afterPermission.activity == .reviewing)
        #expect(afterPermission.activeScopeCount == 1)
        #expect(afterPermission.activeScopes.first?.activity == .reviewing)
    }

    @Test("legacy Claude background stops and idle notifications are terminal")
    func legacyClaudeBackgroundRecordsDoNotRemainActive() {
        let log = """
        {"event":"prompt_submitted","timestamp":100,"provider":"claude","session_id":"claude-session"}
        {"event":"tool_started","timestamp":110,"provider":"claude","session_id":"claude-session","hook_event_name":"Stop"}
        {"event":"permission_requested","timestamp":170,"provider":"claude","session_id":"claude-session","hook_event_name":"Notification"}
        {"event":"prompt_submitted","timestamp":100,"provider":"claude","session_id":"claude-parent"}
        {"event":"tool_started","timestamp":115,"provider":"claude","session_id":"claude-parent","hook_event_name":"SubagentStop","status":"background_active"}
        """

        let snapshot = CodexPetEventLog.snapshot(
            jsonLines: log,
            now: Date(timeIntervalSince1970: 180),
            activeWindow: 600
        )

        #expect(snapshot.activity == .idle)
        #expect(snapshot.activeScopes.isEmpty)
        #expect(snapshot.activeSessionIDs.isEmpty)
    }

    @Test("Claude actionable notifications request attention while ordinary notifications are ignored")
    func claudeNotificationAttentionIsSelective() {
        let actionableLog = """
        {"event":"permission_requested","timestamp":100,"provider":"claude","session_id":"permission","turn_id":"turn-a","hook_event_name":"Notification","status":"permission_prompt"}
        {"event":"permission_requested","timestamp":101,"provider":"claude","session_id":"elicitation","turn_id":"turn-b","hook_event_name":"Notification","status":"ELICITATION_DIALOG"}
        """
        let ordinaryLog = """
        {"event":"permission_requested","timestamp":100,"provider":"claude","session_id":"idle","hook_event_name":"Notification","status":"idle_prompt"}
        {"event":"permission_requested","timestamp":101,"provider":"claude","session_id":"auth","hook_event_name":"Notification","status":"auth_success"}
        {"event":"permission_requested","timestamp":102,"provider":"claude","session_id":"historical","hook_event_name":"Notification"}
        """

        let actionable = CodexPetEventLog.snapshot(
            jsonLines: actionableLog,
            now: Date(timeIntervalSince1970: 102)
        )
        let ordinary = CodexPetEventLog.snapshot(
            jsonLines: ordinaryLog,
            now: Date(timeIntervalSince1970: 103)
        )

        #expect(actionable.activity == .reviewing)
        #expect(actionable.activeScopes.map(\.activity) == [.reviewing, .reviewing])
        #expect(actionable.activeSessionIDs == ["claude:elicitation", "claude:permission"])
        #expect(ordinary.activity == nil)
        #expect(ordinary.activeScopes.isEmpty)
    }

    @Test("a completed turn ignores delayed attention and failure until a genuine new turn")
    func terminalStateIsAuthoritativeWithinTurn() {
        let completedTurn = """
        {"event":"prompt_submitted","timestamp":100,"provider":"claude","session_id":"claude-session","turn_id":"turn-a"}
        {"event":"stopped","timestamp":110,"provider":"claude","session_id":"claude-session","turn_id":"turn-a","hook_event_name":"Stop"}
        {"event":"permission_requested","timestamp":111,"provider":"claude","session_id":"claude-session","turn_id":"turn-a","hook_event_name":"PermissionRequest"}
        {"event":"tool_failed","timestamp":112,"provider":"claude","session_id":"claude-session","turn_id":"turn-a","hook_event_name":"PostToolUseFailure"}
        """
        let newTurn = completedTurn + """

        {"event":"prompt_submitted","timestamp":120,"provider":"claude","session_id":"claude-session","turn_id":"turn-b"}
        {"event":"permission_requested","timestamp":121,"provider":"claude","session_id":"claude-session","turn_id":"turn-b","hook_event_name":"Notification","status":"permission_prompt"}
        {"event":"tool_failed","timestamp":122,"provider":"claude","session_id":"claude-session","turn_id":"turn-a","hook_event_name":"PostToolUseFailure"}
        {"event":"stopped","timestamp":123,"provider":"claude","session_id":"claude-session","turn_id":"turn-a","hook_event_name":"Stop"}
        """

        let terminal = CodexPetEventLog.snapshot(
            jsonLines: completedTurn,
            now: Date(timeIntervalSince1970: 113)
        )
        let restarted = CodexPetEventLog.snapshot(
            jsonLines: newTurn,
            now: Date(timeIntervalSince1970: 124)
        )

        #expect(terminal.activity == .idle)
        #expect(terminal.activeScopes.isEmpty)
        #expect(restarted.activity == .reviewing)
        #expect(restarted.activeScopes.map(\.activity) == [.reviewing])
        #expect(restarted.activeSessionIDs == ["claude:claude-session"])
    }

    @Test("tool completions discover briefly, refresh live work, and never resurrect stopped work")
    func toolCompletionLifecycleIsBounded() {
        let discoveryOnly = #"{"event":"tool_succeeded","timestamp":100,"provider":"cursor","session_id":"discovered","hook_event_name":"postToolUse"}"#
        let established = """
        {"event":"prompt_submitted","timestamp":50,"provider":"cursor","session_id":"established"}
        {"event":"tool_succeeded","timestamp":100,"provider":"cursor","session_id":"established","hook_event_name":"postToolUse"}
        """
        let stopped = """
        {"event":"prompt_submitted","timestamp":100,"provider":"codex","session_id":"stopped"}
        {"event":"stopped","timestamp":110,"provider":"codex","session_id":"stopped","hook_event_name":"Stop"}
        {"event":"tool_succeeded","timestamp":111,"provider":"codex","session_id":"stopped","hook_event_name":"PostToolUse"}
        """

        let duringGrace = CodexPetEventLog.snapshot(
            jsonLines: discoveryOnly,
            now: Date(timeIntervalSince1970: 130),
            activeWindow: 100
        )
        let afterGrace = CodexPetEventLog.snapshot(
            jsonLines: discoveryOnly,
            now: Date(timeIntervalSince1970: 131),
            activeWindow: 100
        )
        let refreshed = CodexPetEventLog.snapshot(
            jsonLines: established,
            now: Date(timeIntervalSince1970: 131),
            activeWindow: 100
        )
        let notResurrected = CodexPetEventLog.snapshot(
            jsonLines: stopped,
            now: Date(timeIntervalSince1970: 112),
            activeWindow: 100
        )

        #expect(duringGrace.activeSessionIDs == ["cursor:discovered"])
        #expect(afterGrace.activity == nil)
        #expect(afterGrace.activeScopes.isEmpty)
        #expect(refreshed.activeSessionIDs == ["cursor:established"])
        #expect(notResurrected.activity == .idle)
        #expect(notResurrected.activeScopes.isEmpty)
    }

    @Test("opaque Cursor subagent hooks do not create duplicate scopes")
    func cursorOpaqueSubagentScopesAreIgnored() {
        let log = """
        {"event":"tool_started","timestamp":100,"provider":"cursor","session_id":"parent:subagent:opaque","parent_session_id":"parent","hook_event_name":"subagentStart"}
        {"event":"tool_failed","timestamp":101,"provider":"cursor","session_id":"parent:subagent:opaque","parent_session_id":"parent","hook_event_name":"subagentStop"}
        """

        let snapshot = CodexPetEventLog.snapshot(
            jsonLines: log,
            now: Date(timeIntervalSince1970: 102)
        )

        #expect(snapshot.activity == nil)
        #expect(snapshot.activeScopes.isEmpty)
        #expect(snapshot.activeSessionIDs.isEmpty)
    }

    @Test("stopped and stale scopes are excluded without cancelling other sessions")
    func stoppedAndStaleScopesAreExcluded() {
        let log = """
        {"event":"tool_started","timestamp":270,"provider":"codex","workspace":"/workspace","session_id":"stopped"}
        {"event":"stopped","timestamp":290,"provider":"codex","workspace":"/workspace","session_id":"stopped"}
        {"event":"tool_started","timestamp":100,"provider":"claude","workspace":"/workspace","session_id":"stale"}
        {"event":"tool_started","timestamp":285,"provider":"cursor","workspace":"/workspace","session_id":"live"}
        """

        let snapshot = CodexPetEventLog.snapshot(
            jsonLines: log,
            now: Date(timeIntervalSince1970: 300),
            activeWindow: 30,
            reviewWindow: 900
        )

        #expect(snapshot.activity == .running)
        #expect(snapshot.activeScopeCount == 1)
        #expect(snapshot.activeScopes.map(\.provider) == [.cursor])
        #expect(snapshot.activeScopes.map(\.activity) == [.running])
        #expect(snapshot.activeSessionIDs == ["cursor:live"])
    }

    @Test("recent failures remain provider-scoped attention while stale failures expire")
    func failuresRemainProviderScopedUntilStale() {
        let log = """
        {"event":"tool_failed","timestamp":280,"provider":"claude","workspace":"/workspace","session_id":"failed-a"}
        {"event":"tool_failed","timestamp":285,"provider":"claude","workspace":"/workspace","session_id":"failed-b"}
        {"event":"tool_failed","timestamp":-700,"provider":"cursor","workspace":"/workspace","session_id":"stale-failure"}
        """

        let snapshot = CodexPetEventLog.snapshot(
            jsonLines: log,
            now: Date(timeIntervalSince1970: 300),
            activeWindow: 30,
            reviewWindow: 900
        )

        #expect(snapshot.activity == .failed)
        #expect(snapshot.activeScopeCount == 2)
        #expect(snapshot.activeScopes.map(\.provider) == [.claude, .claude])
        #expect(snapshot.activeScopes.map(\.activity) == [.failed, .failed])
        #expect(snapshot.activeSessionIDs == ["claude:failed-a", "claude:failed-b"])
    }

    @Test("failure flags use the same attention window as waiting flags")
    func failuresUseAttentionWindow() {
        let log = #"{"event":"tool_failed","timestamp":100,"provider":"cursor","workspace":"/workspace","session_id":"failed"}"#
        let retained = CodexPetEventLog.snapshot(
            jsonLines: log,
            now: Date(timeIntervalSince1970: 300),
            activeWindow: 30,
            reviewWindow: 900
        )
        let expired = CodexPetEventLog.snapshot(
            jsonLines: log,
            now: Date(timeIntervalSince1970: 1_100),
            activeWindow: 30,
            reviewWindow: 900
        )

        #expect(retained.activeScopes.first?.provider == .cursor)
        #expect(retained.activeScopes.first?.activity == .failed)
        #expect(expired.activeScopes.isEmpty)
    }

    @Test("mixed-provider attention clears independently")
    func mixedProviderAttentionClearsIndependently() {
        let initialLog = """
        {"event":"tool_started","timestamp":100,"provider":"codex","workspace":"/workspace","session_id":"codex-running"}
        {"event":"permission_requested","timestamp":101,"provider":"claude","workspace":"/workspace","session_id":"claude-waiting"}
        {"event":"tool_failed","timestamp":102,"provider":"cursor","workspace":"/workspace","session_id":"cursor-failed"}
        """
        let initial = CodexPetEventLog.snapshot(
            jsonLines: initialLog,
            now: Date(timeIntervalSince1970: 105),
            activeWindow: 30,
            reviewWindow: 900
        )
        let cursorCleared = CodexPetEventLog.snapshot(
            jsonLines: initialLog + "\n" + #"{"event":"stopped","timestamp":106,"provider":"cursor","workspace":"/workspace","session_id":"cursor-failed"}"#,
            now: Date(timeIntervalSince1970: 107),
            activeWindow: 30,
            reviewWindow: 900
        )

        #expect(initial.activeScopes.map(\.provider) == [.codex, .claude, .cursor])
        #expect(initial.activeScopes.map(\.activity) == [.running, .reviewing, .failed])
        #expect(cursorCleared.activeScopes.map(\.provider) == [.codex, .claude])
        #expect(cursorCleared.activeScopes.map(\.activity) == [.running, .reviewing])
    }

    @Test("cached activity reuses parsed events while still expiring old running events")
    func cachedActivityReusesParsedEventsWhileStillExpiringOldRunningEvents() throws {
        let url = try temporaryEventLog(
            contents: """
            {"event":"tool_started","timestamp":100}
            """
        )
        var snapshot: CodexPetEventLogSnapshot?

        let active = try CodexPetEventLog.activity(
            in: url,
            now: Date(timeIntervalSince1970: 110),
            activeWindow: 90,
            snapshot: &snapshot
        )
        let cachedSnapshot = try #require(snapshot)

        let expired = try CodexPetEventLog.activity(
            in: url,
            now: Date(timeIntervalSince1970: 250),
            activeWindow: 90,
            snapshot: &snapshot
        )

        #expect(active == .running)
        #expect(expired == nil)
        #expect(snapshot == cachedSnapshot)
    }

    @Test("cached activity refreshes when the event log changes")
    func cachedActivityRefreshesWhenEventLogChanges() throws {
        let url = try temporaryEventLog(
            contents: """
            {"event":"tool_started","timestamp":100}
            """
        )
        var snapshot: CodexPetEventLogSnapshot?

        _ = try CodexPetEventLog.activity(
            in: url,
            now: Date(timeIntervalSince1970: 110),
            snapshot: &snapshot
        )
        let runningSnapshot = try #require(snapshot)

        try """
        {"event":"tool_started","timestamp":100}
        {"event":"stopped","timestamp":111}
        """
        .write(to: url, atomically: true, encoding: .utf8)

        let stopped = try CodexPetEventLog.activity(
            in: url,
            now: Date(timeIntervalSince1970: 112),
            snapshot: &snapshot
        )

        #expect(stopped == .idle)
        #expect(snapshot != runningSnapshot)
    }

    @Test("startup reads the rotated backup before the complete active log")
    func startupReadsAllRetainedLogsInRotationOrder() throws {
        let url = try temporaryEventLog(contents: "")
        let backupURL = URL(fileURLWithPath: url.path + ".1")
        try #"{"event":"permission_requested","timestamp":190,"provider":"claude","session_id":"claude-quiet"}"#
            .appending("\n")
            .write(to: backupURL, atomically: true, encoding: .utf8)

        let cursor = #"{"event":"tool_started","timestamp":191,"provider":"cursor","session_id":"cursor-early"}"#
        let noisyCodex = (0..<5_000).map { index in
            #"{"event":"tool_succeeded","timestamp":\#(192 + (Double(index) / 100_000)),"provider":"codex","session_id":"codex-noisy"}"#
        }
        try ([cursor] + noisyCodex)
            .joined(separator: "\n")
            .appending("\n")
            .write(to: url, atomically: true, encoding: .utf8)

        let retained = try CodexPetEventLog.retainedEvents(from: url)
        var cache: CodexPetEventLogSnapshot?
        let snapshot = try CodexPetEventLog.snapshot(
            in: url,
            now: Date(timeIntervalSince1970: 200),
            tailByteLimit: 64,
            snapshot: &cache
        )

        #expect(retained.events.count == 5_002)
        #expect(retained.events.first?.provider == .claude)
        #expect(retained.events.dropFirst().first?.provider == .cursor)
        #expect(retained.activeReadOffset == retained.activeFileSize)
        #expect(snapshot.activeScopes.map(\.provider) == [.codex, .claude, .cursor])
        #expect(snapshot.activeSessionIDs == ["codex-noisy", "claude:claude-quiet", "cursor:cursor-early"])
        #expect(cache?.backupFileSize ?? 0 > 0)
    }

    @Test("cached snapshots refresh when the rotated backup changes")
    func cachedSnapshotTracksRotatedBackup() throws {
        let url = try temporaryEventLog(
            contents: #"{"event":"tool_started","timestamp":101,"provider":"codex","session_id":"active"}"#
        )
        var cache: CodexPetEventLogSnapshot?
        let initial = try CodexPetEventLog.snapshot(
            in: url,
            now: Date(timeIntervalSince1970: 105),
            snapshot: &cache
        )

        let backupURL = URL(fileURLWithPath: url.path + ".1")
        try #"{"event":"permission_requested","timestamp":100,"provider":"claude","session_id":"backup"}"#
            .appending("\n")
            .write(to: backupURL, atomically: true, encoding: .utf8)
        let refreshed = try CodexPetEventLog.snapshot(
            in: url,
            now: Date(timeIntervalSince1970: 105),
            snapshot: &cache
        )

        #expect(initial.activeScopes.map(\.provider) == [.codex])
        #expect(refreshed.activeScopes.map(\.provider) == [.codex, .claude])
        #expect(cache?.backupFileSize ?? 0 > 0)
    }

    @Test("compaction reserves the latest event for every provider session")
    func compactionPreservesQuietProviderScope() {
        let quietCursor = CodexPetEvent(
            kind: "permission_requested",
            timestamp: 100,
            provider: .cursor,
            workspace: "/quiet",
            sessionID: "cursor-quiet"
        )
        let futureCursorEvent = CodexPetEvent(
            kind: "future_event",
            timestamp: 100.5,
            provider: .cursor,
            workspace: "/quiet",
            sessionID: "cursor-quiet"
        )
        let noisyCodex = (0..<5_000).map { index in
            CodexPetEvent(
                kind: "tool_succeeded",
                timestamp: 101 + (Double(index) / 100_000),
                provider: .codex,
                workspace: "/noisy",
                sessionID: "codex-noisy"
            )
        }

        let compacted = CodexPetEventLog.compactedEvents(
            [quietCursor, futureCursorEvent] + noisyCodex,
            now: Date(timeIntervalSince1970: 110),
            retentionWindow: 600,
            maximumCount: 4_096
        )
        let snapshot = CodexPetEventLog.snapshot(
            events: compacted,
            now: Date(timeIntervalSince1970: 110),
            activeWindow: 90,
            reviewWindow: 900
        )

        #expect(compacted.count == 2)
        #expect(compacted.contains(quietCursor))
        #expect(compacted.last?.timestamp == noisyCodex.last?.timestamp)
        #expect(snapshot.activeScopes.map(\.provider) == [.codex, .cursor])
        #expect(snapshot.activeScopes.map(\.activity) == [.running, .reviewing])
    }

    @Test("compaction remains bounded when unique sessions exceed its budget")
    func compactionBoundsUniqueSessions() {
        let events = (0..<5_000).map { index in
            CodexPetEvent(
                kind: "tool_started",
                timestamp: Double(index),
                provider: .claude,
                sessionID: "session-\(index)"
            )
        }

        let compacted = CodexPetEventLog.compactedEvents(
            events,
            now: Date(timeIntervalSince1970: 5_000),
            retentionWindow: 10_000,
            maximumCount: 4_096
        )

        #expect(compacted.count == 4_096)
        #expect(compacted.first?.sessionID == "session-904")
        #expect(compacted.last?.sessionID == "session-4999")
    }
}

private func temporaryEventLog(contents: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("CodexPetEventLogTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("pet-events.jsonl")
    try (contents + "\n").write(to: url, atomically: true, encoding: .utf8)
    return url
}

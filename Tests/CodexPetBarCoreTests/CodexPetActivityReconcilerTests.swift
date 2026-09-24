import Foundation
import Testing
@testable import CodexPetBarCore

@Suite("Codex pet activity reconciliation")
struct CodexPetActivityReconcilerTests {
    @Test("adds missing Codex threads while preserving provider attention and sessions")
    func addsMissingCodexThreadsAndPreservesProviders() throws {
        let snapshot = CodexPetEventLog.snapshot(
            events: [
                CodexPetEvent(
                    kind: "tool_failed",
                    timestamp: 100,
                    provider: .codex,
                    sessionID: "hook-codex"
                ),
                CodexPetEvent(
                    kind: "tool_started",
                    timestamp: 101,
                    provider: .claude,
                    sessionID: "shared"
                ),
                CodexPetEvent(
                    kind: "permission_requested",
                    timestamp: 102,
                    provider: .cursor,
                    sessionID: "cursor-waiting"
                ),
            ],
            now: Date(timeIntervalSince1970: 105),
            activeWindow: 30,
            reviewWindow: 900
        )

        let reconciled = CodexPetActivityReconciler.merging(
            snapshot: snapshot,
            runningCodexThreadIDs: ["scanner-only", "hook-codex", "scanner-only", ""]
        )

        #expect(reconciled.activity == .reviewing)
        #expect(reconciled.activeScopeCount == 4)
        #expect(reconciled.activeScopes.map(\.provider) == [.codex, .codex, .claude, .cursor])
        #expect(reconciled.activeScopes.filter { $0.provider == .codex }.map(\.activity) == [.failed, .running])
        #expect(
            reconciled.activeSessionIDs == [
                "hook-codex",
                "scanner-only",
                "claude:shared",
                "cursor:cursor-waiting",
            ]
        )
    }

    @Test("synthesized Codex scopes use the event log identity format")
    func synthesizedScopeUsesEventLogIdentityFormat() throws {
        let threadID = "019f842c-c312-7332-afec-d21d912578b7"
        let hookSnapshot = CodexPetEventLog.snapshot(
            events: [
                CodexPetEvent(
                    kind: "tool_started",
                    timestamp: 100,
                    provider: .codex,
                    workspace: "/workspace/ignored-for-session-scope",
                    sessionID: threadID,
                    turnID: "turn-ignored-for-session-scope"
                ),
            ],
            now: Date(timeIntervalSince1970: 101)
        )
        let reconciled = CodexPetActivityReconciler.merging(
            snapshot: CodexPetActivitySnapshot(
                activity: nil,
                activeSessionIDs: [],
                activeScopeCount: 0
            ),
            runningCodexThreadIDs: [threadID]
        )

        let hookScope = try #require(hookSnapshot.activeScopes.first)
        let synthesizedScope = try #require(reconciled.activeScopes.first)
        #expect(synthesizedScope.scopedIdentity == hookScope.scopedIdentity)
        #expect(synthesizedScope.activity == .running)
        #expect(reconciled.activeSessionIDs == [threadID])
        #expect(reconciled.activity == .running)
    }

    @Test("ordering and duplicate resolution are deterministic")
    func outputIsDeterministic() {
        let codexIdentity = CodexPetActivityReconciler.codexSessionScopedIdentity(threadID: "codex-existing")
        let scopes = [
            CodexPetActiveScope(provider: .cursor, scopedIdentity: "cursor-z", activity: .running),
            CodexPetActiveScope(provider: .claude, scopedIdentity: "claude-a", activity: .reviewing),
            CodexPetActiveScope(provider: .codex, scopedIdentity: codexIdentity, activity: .listening),
            CodexPetActiveScope(provider: .codex, scopedIdentity: codexIdentity, activity: .failed),
        ]
        let forward = CodexPetActivitySnapshot(
            activity: .reviewing,
            activeSessionIDs: ["codex-existing", "claude:claude-a", "cursor:cursor-z"],
            activeScopeCount: scopes.count,
            activeScopes: scopes
        )
        let reversed = CodexPetActivitySnapshot(
            activity: .reviewing,
            activeSessionIDs: forward.activeSessionIDs,
            activeScopeCount: scopes.count,
            activeScopes: scopes.reversed()
        )

        let forwardResult = CodexPetActivityReconciler.merging(
            snapshot: forward,
            runningCodexThreadIDs: ["codex-z", "codex-a", "codex-existing"]
        )
        let reversedResult = CodexPetActivityReconciler.merging(
            snapshot: reversed,
            runningCodexThreadIDs: ["codex-existing", "codex-a", "codex-z"]
        )

        #expect(forwardResult == reversedResult)
        #expect(forwardResult.activeScopes.map(\.provider) == [.codex, .codex, .codex, .claude, .cursor])
        #expect(forwardResult.activeScopes.first { $0.scopedIdentity == codexIdentity }?.activity == .failed)
        #expect(forwardResult.activeScopeCount == 5)
        #expect(forwardResult.activity == .reviewing)
    }

    @Test("same raw provider session remains distinct from scanner Codex session")
    func sameRawSessionAcrossProvidersRemainsDistinct() {
        let claudeSnapshot = CodexPetEventLog.snapshot(
            events: [
                CodexPetEvent(
                    kind: "tool_started",
                    timestamp: 100,
                    provider: .claude,
                    sessionID: "shared"
                ),
            ],
            now: Date(timeIntervalSince1970: 101)
        )

        let reconciled = CodexPetActivityReconciler.merging(
            snapshot: claudeSnapshot,
            runningCodexThreadIDs: ["shared"]
        )

        #expect(reconciled.activeScopes.map(\.provider) == [.codex, .claude])
        #expect(reconciled.activeSessionIDs == ["shared", "claude:shared"])
        #expect(reconciled.activeScopeCount == 2)
    }

    @Test("explicit rollout completion clears only its matching Codex hook scope")
    func explicitRolloutCompletionClearsMatchingCodexScope() {
        let snapshot = CodexPetEventLog.snapshot(
            events: [
                CodexPetEvent(kind: "tool_started", timestamp: 100, provider: .codex, sessionID: "done"),
                CodexPetEvent(
                    kind: "tool_started",
                    timestamp: 100,
                    provider: .codex,
                    sessionID: "done:subagent:child",
                    parentSessionID: "done"
                ),
                CodexPetEvent(kind: "tool_started", timestamp: 100, provider: .codex, sessionID: "still-running"),
                CodexPetEvent(kind: "tool_started", timestamp: 100, provider: .claude, sessionID: "done"),
            ],
            now: Date(timeIntervalSince1970: 101)
        )

        let reconciled = CodexPetActivityReconciler.merging(
            snapshot: snapshot,
            runningCodexThreadIDs: ["still-running"],
            completedCodexThreadIDs: ["done"]
        )

        #expect(reconciled.activeScopes.map(\.provider) == [.codex, .claude])
        #expect(reconciled.activeSessionIDs == ["still-running", "claude:done"])
        #expect(reconciled.activeScopeCount == 2)
        #expect(reconciled.activity == .running)
    }

    @Test("running rollout state wins over an inconsistent completion set")
    func runningRolloutWinsOverCompletion() {
        let reconciled = CodexPetActivityReconciler.merging(
            snapshot: CodexPetActivitySnapshot(
                activity: nil,
                activeSessionIDs: [],
                activeScopeCount: 0
            ),
            runningCodexThreadIDs: ["same"],
            completedCodexThreadIDs: ["same"]
        )

        #expect(reconciled.activeSessionIDs == ["same"])
        #expect(reconciled.activeScopes.first?.activity == .running)
    }

    @Test("scanner keeps a running child distinct when its parent completed")
    func scannerKeepsRunningChildWhenParentCompleted() throws {
        let snapshot = CodexPetEventLog.snapshot(
            events: [
                CodexPetEvent(kind: "tool_started", timestamp: 100, provider: .codex, sessionID: "parent"),
                CodexPetEvent(
                    kind: "tool_started",
                    timestamp: 100,
                    provider: .codex,
                    sessionID: "child",
                    parentSessionID: "parent"
                ),
            ],
            now: Date(timeIntervalSince1970: 101)
        )

        let reconciled = CodexPetActivityReconciler.merging(
            snapshot: snapshot,
            runningCodexScopes: [
                CodexRolloutActivityScope(
                    sessionID: "child",
                    parentSessionID: "parent",
                    workspace: "/tmp/project",
                    modificationDate: Date(timeIntervalSince1970: 101)
                ),
            ],
            completedCodexScopes: [
                CodexRolloutActivityScope(
                    sessionID: "parent",
                    modificationDate: Date(timeIntervalSince1970: 100)
                ),
            ]
        )

        let child = try #require(reconciled.activeScopes.first)
        #expect(reconciled.activeScopeCount == 1)
        #expect(child.sessionID == "child")
        #expect(child.parentSessionID == "parent")
        #expect(reconciled.activeSessionIDs == ["child"])
    }

    @Test("scanner synthesized child exposes its session and parent ids")
    func scannerSynthesizedChildExposesIdentity() throws {
        let reconciled = CodexPetActivityReconciler.merging(
            snapshot: CodexPetActivitySnapshot(
                activity: nil,
                activeSessionIDs: [],
                activeScopeCount: 0
            ),
            runningCodexScopes: [
                CodexRolloutActivityScope(sessionID: "child", parentSessionID: "parent"),
            ]
        )

        let child = try #require(reconciled.activeScopes.first)
        #expect(child.sessionID == "child")
        #expect(child.parentSessionID == "parent")
        #expect(child.activity == .running)
    }

    @Test("scanner metadata enriches a hook scope missing its parent id")
    func scannerMetadataEnrichesHookScope() throws {
        let snapshot = CodexPetEventLog.snapshot(
            events: [
                CodexPetEvent(
                    kind: "permission_requested",
                    timestamp: 100,
                    provider: .codex,
                    sessionID: "child"
                ),
            ],
            now: Date(timeIntervalSince1970: 101)
        )
        let reconciled = CodexPetActivityReconciler.merging(
            snapshot: snapshot,
            runningCodexScopes: [
                CodexRolloutActivityScope(sessionID: "child", parentSessionID: "parent"),
            ]
        )

        let child = try #require(reconciled.activeScopes.first)
        #expect(child.activity == .reviewing)
        #expect(child.parentSessionID == "parent")
    }
}

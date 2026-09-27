import Foundation
import Testing
@testable import CodexPetBarCore

@Suite("Codex running evidence freshness")
struct CodexRunningFreshnessTests {
    private let start: TimeInterval = 1_000

    @Test("established Codex hooks expire immediately after one hour")
    func establishedHooksExpireAtOneHour() {
        let events = [event("tool_started", at: start)]
        let boundary = start + 60 * 60

        #expect(CodexPetActivityFreshness.codexRunningWindow == 60 * 60)
        #expect(snapshot(events, at: boundary).activeSessionIDs == ["task"])
        #expect(snapshot(events, at: boundary + 0.001).activeScopes.isEmpty)
        #expect(snapshot(events, at: start + 4 * 60 * 60).activity == nil)
    }

    @Test("a caller's shorter running window remains authoritative")
    func shorterConfiguredWindowWins() {
        let events = [event("prompt_submitted", at: start)]

        #expect(snapshot(events, at: start + 45, activeWindow: 45).activity == .running)
        #expect(snapshot(events, at: start + 46, activeWindow: 45).activeScopes.isEmpty)
        #expect(snapshot(events, at: start + 1, activeWindow: 0).activeScopes.isEmpty)
    }

    @Test("fresh callbacks renew running while late discovery keeps its thirty-second grace")
    func completionEvidencePreservesItsMeaning() {
        let running = event("tool_started", at: start)
        let timely = [running, event("tool_succeeded", at: start + 3_599)]
        let late = [running, event("tool_succeeded", at: start + 3_601)]

        #expect(snapshot(timely, at: start + 7_199).activity == .running)
        #expect(snapshot(timely, at: start + 7_200).activeScopes.isEmpty)
        #expect(snapshot(late, at: start + 3_631).activity == .running)
        #expect(snapshot(late, at: start + 3_632).activeScopes.isEmpty)
    }

    @Test("permission and failure attention retain their full twenty-four-hour window")
    func attentionRetentionIsUnchanged() {
        for kind in ["permission_requested", "tool_failed"] {
            let events = [event(kind, at: start)]
            let expected: CodexActivity = kind == "permission_requested" ? .reviewing : .failed
            #expect(snapshot(events, at: start + 86_400, activeWindow: 10).activity == expected)
            #expect(snapshot(events, at: start + 86_401, activeWindow: 10).activeScopes.isEmpty)
        }
    }

    @Test("Claude and Cursor keep their existing thirty-minute running lease")
    func otherProviderLeaseIsUnchanged() {
        for provider in [PetProvider.claude, .cursor] {
            let events = [event("tool_started", at: start, provider: provider)]
            #expect(snapshot(events, at: start + 1_800).activity == .running)
            #expect(snapshot(events, at: start + 1_801).activeScopes.isEmpty)
        }
        #expect(snapshot([event("tool_started", at: start)], at: start + 1_801).activity == .running)
    }

    @Test("fresh verified rollout evidence can restore an expired hook session")
    func freshRolloutRestoresRunning() {
        let now = start + 3_601
        let hooks = snapshot([event("tool_started", at: start)], at: now)
        #expect(hooks.activeScopes.isEmpty)

        let reconciled = CodexPetActivityReconciler.merging(snapshot: hooks, runningCodexScopes: [
            CodexRolloutActivityScope(sessionID: "task", modificationDate: Date(timeIntervalSince1970: now),
                                     marker: .init(state: .running, turnID: "turn", timestamp: now)),
        ])

        #expect(reconciled.activity == .running)
        #expect(reconciled.activeSessionIDs == ["task"])
        #expect(reconciled.activeScopes.first?.timestamp == now)
    }

    @Test("retained lifecycle checkpoints apply the same running expiry")
    func checkpointsCannotExtendFreshness() {
        let events = [event("prompt_submitted", at: start), event("tool_succeeded", at: start + 10)]
        let now = Date(timeIntervalSince1970: start + 3_611)
        let retained = CodexPetEventLog.compactedEvents(events, now: now, retentionWindow: 86_400, maximumCount: 1)

        #expect(retained.count == 1)
        #expect(retained.first?.lifecycleCheckpoint != nil)
        #expect(CodexPetEventLog.snapshot(events: retained, now: now).activeScopes.isEmpty)
        #expect(CodexPetEventLog.snapshot(events: retained, now: now)
            == CodexPetEventLog.snapshot(events: events, now: now))
    }

    private func event(_ kind: String, at timestamp: TimeInterval, provider: PetProvider = .codex) -> CodexPetEvent {
        CodexPetEvent(kind: kind, timestamp: timestamp, provider: provider, sessionID: "task", turnID: "turn")
    }

    private func snapshot(
        _ events: [CodexPetEvent], at timestamp: TimeInterval, activeWindow: TimeInterval = 6 * 60 * 60
    ) -> CodexPetActivitySnapshot {
        CodexPetEventLog.snapshot(events: events, now: Date(timeIntervalSince1970: timestamp), activeWindow: activeWindow)
    }
}

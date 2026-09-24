import Foundation
import Testing
@testable import CodexPetBarCore

@Suite("Rollout and hook precedence")
struct CodexRolloutHookPrecedenceTests {
    @Test("a fresh prompt wakes a session before its completed scan refreshes")
    func freshPromptBeatsCompletedScan() {
        let old = scope(.completed, at: 110, turn: "a")
        #expect(filtered(old, [hook("prompt_submitted", at: 120, turn: "b")]).isEmpty)
    }

    @Test("a fresh stop beats cached running activity")
    func freshStopBeatsRunningScan() {
        #expect(filtered(scope(.running, at: 110), [hook("stopped", at: 120)]).isEmpty)
    }

    @Test("file mtime cannot make an old terminal marker win again")
    func markerTimeBeatsFileTime() {
        let hooks = [hook("prompt_submitted", at: 120, turn: "b")]
        for modified in [115.0, 150.0, 999.0] {
            #expect(filtered(scope(.completed, at: 110, modified: modified), hooks).isEmpty)
        }
    }

    @Test("newer and equal-time scan evidence remains authoritative")
    func newerScanSurvives() {
        for time in [120.0, 130.0] {
            let current = scope(.running, at: time, turn: "b")
            #expect(filtered(current, [hook("stopped", at: 120, turn: "a")]) == [current])
        }
    }

    @Test("late same-turn tool or attention hooks do not reopen completion")
    func lateContinuationKeepsCompletion() {
        let completed = scope(.completed, at: 110)
        for kind in ["tool_succeeded", "tool_started", "permission_requested", "tool_failed"] {
            #expect(filtered(completed, [hook(kind, at: 120)]) == [completed])
        }
    }

    @Test("a distinct new turn's work or attention supersedes completion")
    func newTurnWorkBeatsCompletion() {
        for kind in ["prompt_submitted", "tool_started", "edit_started", "permission_requested"] {
            #expect(filtered(scope(.completed, at: 110), [hook(kind, at: 120, turn: "b")]).isEmpty)
        }
    }

    @Test("a prompt without turn IDs can resume a completed session")
    func identifierFreePromptResumes() {
        #expect(filtered(scope(.completed, at: 110, turn: nil), [hook("prompt_submitted", at: 120, turn: nil)]).isEmpty)
    }

    @Test("new attention supersedes running scan activity")
    func attentionBeatsRunningScan() {
        for kind in ["permission_requested", "tool_failed"] {
            #expect(filtered(scope(.running, at: 110), [hook(kind, at: 120)]).isEmpty)
        }
    }

    @Test("only a newer parent terminal suppresses a child's scan")
    func parentTerminalBoundsChildren() {
        let oldChild = scope(.running, at: 110, session: "child", parent: "parent")
        let newChild = scope(.running, at: 130, session: "child", parent: "parent")
        let parentStop = hook("stopped", at: 120, session: "parent")
        #expect(filtered(oldChild, [parentStop]).isEmpty)
        #expect(filtered(newChild, [parentStop]) == [newChild])
        #expect(filtered(oldChild, [hook("prompt_submitted", at: 120, session: "parent")]) == [oldChild])
        #expect(filtered(oldChild, [parentStop, hook("prompt_submitted", at: 130, turn: "b", session: "parent")]) == [oldChild])
    }

    @Test("a subagent callback on the parent session does not stop sibling scans")
    func subagentCallbackDoesNotStopSiblings() {
        let sibling = scope(.running, at: 110, session: "child", parent: "parent")
        let childCallback = CodexPetEvent(kind: "stopped", timestamp: 120, provider: .codex,
                                         sessionID: "parent", hookEventName: "SubagentStop")
        #expect(filtered(sibling, [childCallback]) == [sibling])
    }

    @Test("other providers, sessions, notifications and invalid timestamps cannot override")
    func ignoresUnrelatedEvents() {
        let running = scope(.running, at: 110)
        let events = [
            hook("stopped", at: 120, provider: .claude),
            hook("stopped", at: 120, session: "another"),
            hook("notification", at: 120),
            hook("stopped", at: .infinity),
            hook("stopped", at: .nan)
        ]
        #expect(filtered(running, events) == [running])
    }

    @Test("scanner-only sessions and scope ordering are preserved")
    func noHookOperationIsUnchanged() {
        let scopes = [scope(.running, at: 110, session: "b"), scope(.completed, at: 120, session: "a")]
        #expect(CodexRolloutHookPrecedence.filter(scopes: scopes, events: []) == scopes)
    }

    @Test("legacy scopes use mtime only when no record timestamp is available")
    func legacyFallback() {
        for marker in [CodexRunningThreadLog.Marker?.none, .some(.init(state: .running, turnID: "a"))] {
            let legacy = CodexRolloutActivityScope(sessionID: "session", modificationDate: Date(timeIntervalSince1970: 110), marker: marker)
            #expect(filtered(legacy, [hook("stopped", at: 120)]).isEmpty)
            #expect(filtered(legacy, [hook("stopped", at: 100)]) == [legacy])
        }
    }

    private func filtered(_ scope: CodexRolloutActivityScope, _ events: [CodexPetEvent]) -> [CodexRolloutActivityScope] {
        CodexRolloutHookPrecedence.filter(scopes: [scope], events: events)
    }

    private func scope(
        _ state: CodexRunningThreadLog.State, at timestamp: Double,
        modified: Double? = nil, turn: String? = "a", session: String = "session", parent: String? = nil
    ) -> CodexRolloutActivityScope {
        CodexRolloutActivityScope(
            sessionID: session, parentSessionID: parent,
            modificationDate: Date(timeIntervalSince1970: modified ?? timestamp),
            marker: .init(state: state, completionOutcome: state == .completed ? .success : nil, turnID: turn, timestamp: timestamp)
        )
    }

    private func hook(
        _ kind: String, at timestamp: Double, turn: String? = "a", session: String = "session", provider: PetProvider = .codex
    ) -> CodexPetEvent {
        CodexPetEvent(kind: kind, timestamp: timestamp, provider: provider, sessionID: session, turnID: turn,
                      hookEventName: kind == "stopped" ? "Stop" : nil)
    }
}

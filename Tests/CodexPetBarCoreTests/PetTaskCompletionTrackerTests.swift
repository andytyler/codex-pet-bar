import Foundation
import Testing
@testable import CodexPetBarCore

@Suite("Task completion detection")
struct PetTaskCompletionTrackerTests {
    private let now = Date(timeIntervalSince1970: 200)

    @Test("startup history and the first scan are silent")
    func startupIsSilent() {
        var tracker = makeTracker()
        #expect({ !tracker.consumeHookEvents([hook("prompt_submitted", at: 90), hook("stopped", at: 99)], now: now) }())
        #expect({ !tracker.consumeScan(scan(completed: [scope(at: 110)]), now: now) }())
        #expect({ !tracker.consumeScan(scan(completed: [scope(at: 110, mtime: 190)]), now: now) }())
    }

    @Test("successful stop is emitted once across hook and rollout sources")
    func deduplicatesBothSourceOrders() {
        for hookFirst in [true, false] {
            var tracker = makeTracker()
            #expect({ !tracker.consumeScan(scan(running: [scope(state: .running, at: 105)]), now: now) }())
            let stop = hook("stopped", at: 120)
            let completed = scan(completed: [scope(at: 119)])
            if hookFirst {
                #expect({ tracker.consumeHookEvents([stop], now: now) }())
                #expect({ !tracker.consumeScan(completed, now: now) }())
            } else {
                #expect({ tracker.consumeScan(completed, now: now) }())
                #expect({ !tracker.consumeHookEvents([stop], now: now) }())
            }
            #expect({ !tracker.consumeHookEvents([stop, hook("stopped", at: 125, hookName: "SessionEnd")], now: now) }())
        }
    }

    @Test("old scanner activity cannot rearm a task stopped by a hook")
    func staleScanDoesNotRearm() {
        var tracker = makeTracker()
        #expect({ !tracker.consumeScan(scan(), now: now) }())
        #expect({ !tracker.consumeHookEvents([hook("prompt_submitted", at: 105)], now: now) }())
        #expect({ tracker.consumeHookEvents([hook("stopped", at: 120)], now: now) }())
        #expect({ !tracker.consumeScan(scan(running: [scope(state: .running, at: 110)]), now: now) }())
        #expect({ !tracker.consumeScan(scan(completed: [scope(at: 119)]), now: now) }())
        #expect({ !tracker.consumeScan(scan(completed: [scope(at: 119, mtime: 199)]), now: now) }())
    }

    @Test("a resumed session can finish a second turn")
    func resumedSessionCompletesAgain() {
        var tracker = makeTracker()
        #expect({ !tracker.consumeScan(scan(running: [scope(state: .running, at: 105)]), now: now) }())
        #expect({ tracker.consumeScan(scan(completed: [scope(at: 110)]), now: now) }())
        #expect({ !tracker.consumeScan(scan(running: [scope(state: .running, at: 130, turn: "b")]), now: now) }())
        #expect({ tracker.consumeScan(scan(completed: [scope(at: 140, turn: "b")]), now: now) }())
        #expect({ !tracker.consumeHookEvents([hook("stopped", at: 145, turn: "a")], now: now) }())
    }

    @Test("cancellation, failure, expiry, tool success and child completion are not Done")
    func excludesUnsuccessfulAndNonTaskEvents() {
        var tracker = makeTracker()
        #expect({ !tracker.consumeScan(scan(running: [scope(state: .running, at: 105)]), now: now) }())
        #expect({ !tracker.consumeScan(scan(), now: now) }())
        #expect({ !tracker.consumeScan(scan(completed: [scope(at: 120, outcome: .cancelled)]), now: now) }())
        #expect({ !tracker.consumeHookEvents([
            hook("tool_succeeded", at: 121, hookName: "PostToolUse"),
            hook("stopped", at: 122, turn: "child", parent: "parent"),
            hook("stopped", at: 123, turn: "child", hookName: "SubagentStop"),
            hook("stopped", at: 124, turn: "new", hookName: "SessionEnd"),
            hook("tool_failed", at: 125, turn: "failed", hookName: "StopFailure")
        ], now: now) }())
        #expect({ !tracker.consumeScan(scan(completed: [scope(at: 140, turn: "child", parent: "parent")]), now: now) }())
    }

    @Test("a short distinct turn completed between scans is announced once")
    func turnBetweenScans() {
        var tracker = makeTracker()
        #expect({ !tracker.consumeScan(scan(completed: [scope(at: 110)]), now: now) }())
        #expect({ tracker.consumeScan(scan(completed: [scope(at: 130, turn: "b")]), now: now) }())
        #expect({ !tracker.consumeScan(scan(completed: [scope(at: 130, turn: "b", mtime: 199)]), now: now) }())
        #expect({ !tracker.consumeScan(scan(completed: [scope(at: 110)]), now: now) }())
        #expect({ !tracker.consumeHookEvents([hook("stopped", at: 140, turn: "b")], now: now) }())
    }

    @Test("Cursor requires a final successful stop, not a response or aborted stop")
    func cursorRequiresExplicitSuccess() {
        for status in ["aborted", "cancelled", "error", "failed", "", "unknown"] {
            var tracker = makeTracker()
            #expect({ !tracker.consumeHookEvents([hook("stopped", at: 110, provider: .cursor, hookName: "stop", status: status)], now: now) }())
        }
        var tracker = makeTracker()
        #expect({ !tracker.consumeHookEvents([hook("stopped", at: 110, provider: .cursor, hookName: "afterAgentResponse")], now: now) }())
        #expect({ tracker.consumeHookEvents([hook("stopped", at: 115, provider: .cursor, hookName: "stop", status: "completed")], now: now) }())
    }

    @Test("Claude normal Stop succeeds, and a recovered tool failure is allowed")
    func claudeStopAndRecoveredFailure() {
        var tracker = makeTracker()
        #expect({ tracker.consumeHookEvents([
            hook("prompt_submitted", at: 105, provider: .claude),
            hook("tool_failed", at: 110, provider: .claude, hookName: "PostToolUseFailure"),
            hook("stopped", at: 120, provider: .claude)
        ], now: now) }())
        var failed = makeTracker()
        #expect({ !failed.consumeHookEvents([hook("stopped", at: 120, provider: .claude, status: "background_active")], now: now) }())
    }

    @Test("later new work in the same batch suppresses a stale Done cue")
    func resumedBatchDoesNotFlashDone() {
        var tracker = makeTracker()
        #expect({ !tracker.consumeHookEvents([
            hook("stopped", at: 120),
            hook("prompt_submitted", at: 130, turn: "b"),
            hook("stopped", at: 140, turn: "a")
        ], now: now) }())
        #expect({ tracker.consumeHookEvents([hook("stopped", at: 150, turn: "b")], now: now) }())
    }

    @Test("an old turn cancellation cannot erase the current turn's completion")
    func oldCancellationDoesNotEraseNewCompletion() {
        var tracker = makeTracker()
        #expect({ tracker.consumeHookEvents([
            hook("prompt_submitted", at: 120, turn: "b"),
            hook("stopped", at: 130, turn: "b"),
            hook("stopped", at: 140, turn: "a", status: "aborted")
        ], now: now) }())
    }

    @Test("hooks without turn IDs finish once and can resume after a new prompt")
    func hooksWithoutTurnIDs() {
        var tracker = makeTracker()
        #expect({ tracker.consumeHookEvents([hook("stopped", at: 110, turn: nil)], now: now) }())
        #expect({ !tracker.consumeHookEvents([hook("stopped", at: 115, turn: nil)], now: now) }())
        #expect({ !tracker.consumeHookEvents([hook("tool_succeeded", at: 116, turn: nil)], now: now) }())
        #expect({ !tracker.consumeHookEvents([hook("prompt_submitted", at: 120, turn: nil)], now: now) }())
        #expect({ tracker.consumeHookEvents([hook("stopped", at: 130, turn: nil)], now: now) }())
    }

    @Test("untimestamped success requires observed running and never repeats for mtime")
    func unidentifiedScanRequiresRunning() {
        var tracker = makeTracker()
        #expect({ !tracker.consumeScan(scan(), now: now) }())
        #expect({ !tracker.consumeScan(scan(completed: [scope(at: nil, turn: nil)]), now: now) }())
        #expect({ !tracker.consumeScan(scan(running: [scope(state: .running, at: nil, turn: nil)]), now: now.addingTimeInterval(1)) }())
        #expect({ tracker.consumeScan(scan(completed: [scope(at: nil, turn: nil)]), now: now.addingTimeInterval(2)) }())
        #expect({ !tracker.consumeScan(scan(completed: [scope(at: nil, turn: nil, mtime: 999)]), now: now.addingTimeInterval(3)) }())
    }

    @Test("old and far-future timestamps cannot announce completion")
    func rejectsInvalidFreshness() {
        for timestamp in [99.0, 206.0, .nan, .infinity] {
            var tracker = makeTracker()
            #expect({ !tracker.consumeHookEvents([hook("stopped", at: timestamp)], now: now) }())
        }
        var tracker = makeTracker()
        #expect({ !tracker.consumeScan(scan(), now: now) }())
        #expect({ !tracker.consumeScan(scan(completed: [scope(at: 99)]), now: now) }())
        #expect({ !tracker.consumeScan(scan(completed: [scope(at: 206, turn: "future")]), now: now) }())
    }

    private func makeTracker() -> PetTaskCompletionTracker {
        PetTaskCompletionTracker(startedAt: Date(timeIntervalSince1970: 100))
    }

    private func hook(
        _ kind: String, at timestamp: TimeInterval, turn: String? = "a",
        provider: PetProvider = .codex, parent: String? = nil,
        hookName: String = "Stop", status: String? = nil
    ) -> CodexPetEvent {
        CodexPetEvent(kind: kind, timestamp: timestamp, provider: provider,
                      sessionID: "session", parentSessionID: parent, turnID: turn,
                      hookEventName: kind == "stopped" || kind == "tool_failed" ? hookName : nil,
                      status: status)
    }

    private func scope(
        state: CodexRunningThreadLog.State = .completed,
        at timestamp: TimeInterval?, turn: String? = "a", parent: String? = nil,
        mtime: TimeInterval = 150, outcome: CodexRunningThreadLog.CompletionOutcome = .success
    ) -> CodexRolloutActivityScope {
        CodexRolloutActivityScope(
            sessionID: "session", parentSessionID: parent,
            modificationDate: Date(timeIntervalSince1970: mtime),
            marker: .init(state: state, completionOutcome: state == .completed ? outcome : nil,
                          turnID: turn, timestamp: timestamp)
        )
    }

    private func scan(
        running: [CodexRolloutActivityScope] = [], completed: [CodexRolloutActivityScope] = []
    ) -> CodexRunningThreadScan {
        CodexRunningThreadScan(runningScopes: running, completedScopes: completed)
    }
}

import Foundation
import Testing
@testable import CodexPetBarCore

@Suite("Lifecycle retention and presentation parity")
struct LifecycleRetentionTests {
    private func event(_ kind: String, _ timestamp: Double, session: String = "quiet", turn: String? = "turn-a", tool: String? = nil, request: String? = nil, name: String? = nil) -> CodexPetEvent {
        CodexPetEvent(kind: kind, timestamp: timestamp, provider: .claude, sessionID: session,
            turnID: turn, toolName: name, toolUseID: tool, permissionRequestID: request)
    }

    @Test("parallel callbacks cannot resolve a different pending permission")
    func correlatedApprovals() {
        var events = [event("prompt_submitted", 100), event("tool_started", 101, tool: "read"),
            event("permission_requested", 102, tool: "bash-1", request: "request-1"),
            event("permission_requested", 103, tool: "bash-2", request: "request-2")]
        for kind in ["tool_started", "tool_succeeded", "tool_failed"] {
            #expect(CodexPetEventLog.snapshot(events: events + [event(kind, 104, tool: "read")],
                now: Date(timeIntervalSince1970: 105)).activity == .reviewing)
        }
        events.append(event("tool_succeeded", 105, tool: "bash-1"))
        #expect(CodexPetEventLog.snapshot(events: events, now: Date(timeIntervalSince1970: 106)).activity == .reviewing)
        events.append(event("tool_succeeded", 106, request: "request-2"))
        #expect(CodexPetEventLog.snapshot(events: events, now: Date(timeIntervalSince1970: 107)).activity == .running)
        events += [event("stopped", 108), event("permission_requested", 109, tool: "bash-1")]
        #expect(CodexPetEventLog.snapshot(events: events, now: Date(timeIntervalSince1970: 110)).activity == .idle)
    }

    @Test("uncorrelated permission requires an explicit lifecycle boundary")
    func conservativeUncorrelatedApproval() {
        let events = [event("permission_requested", 100, name: "Bash"),
            event("tool_succeeded", 101, name: "Bash")]
        #expect(CodexPetEventLog.snapshot(events: events, now: Date(timeIntervalSince1970: 102)).activity == .reviewing)
        #expect(CodexPetEventLog.snapshot(events: events + [event("prompt_submitted", 103, turn: "turn-b")],
            now: Date(timeIntervalSince1970: 104)).activity == .running)
    }

    @Test("underlying running evidence survives approval expiry and matching resolution")
    func workEvidenceBehindAttention() {
        let events = [event("prompt_submitted", 0), event("permission_requested", 1, tool: "bash"),
            event("tool_started", 86_390, tool: "read")]
        let noCallbackTime = Date(timeIntervalSince1970: 86_402)
        let noCallbackCompacted = CodexPetEventLog.compactedEvents(events, now: noCallbackTime,
            retentionWindow: 86_400, maximumCount: 1)
        #expect(CodexPetEventLog.snapshot(events: events, now: noCallbackTime).activity == .running)
        #expect(CodexPetEventLog.snapshot(events: noCallbackCompacted, now: noCallbackTime).activity == .running)
        #expect(PetTaskSummaryBuilder.providerTasks(events: events, now: noCallbackTime).first?.status == .running)
        #expect(PetTaskSummaryBuilder.providerTasks(events: noCallbackCompacted, now: noCallbackTime).first?.status == .running)
        for callback in [event("tool_succeeded", 86_402, tool: "read"), event("tool_succeeded", 86_400, tool: "bash")] {
            let full = events + [callback]
            let compacted = CodexPetEventLog.compactedEvents(events, now: Date(timeIntervalSince1970: 86_390),
                retentionWindow: 100_000, maximumCount: 1) + [callback]
            let now = Date(timeIntervalSince1970: 86_450)
            #expect(CodexPetEventLog.snapshot(events: full, now: now).activity == .running)
            #expect(CodexPetEventLog.snapshot(events: compacted, now: now).activity == .running)
        }
    }

    @Test("compaction preserves the pinned project and terminal assistant summary")
    func projectAndSummarySurvive() {
        let events = [CodexPetEvent(kind: "prompt_submitted", timestamp: 100, provider: .claude,
                workspace: "/original", sessionID: "project", turnID: "a"),
            CodexPetEvent(kind: "stopped", timestamp: 110, provider: .claude,
                workspace: "/changed", sessionID: "project", turnID: "a", assistantSummary: "Finished the change"),
            CodexPetEvent(kind: "stopped", timestamp: 111, provider: .claude,
                workspace: "/changed", sessionID: "project", turnID: "a", hookEventName: "SessionEnd")]
        let now = Date(timeIntervalSince1970: 120)
        let compacted = CodexPetEventLog.compactedEvents(events, now: now, retentionWindow: 1000, maximumCount: 1)
        let fullCards = PetTaskSummaryBuilder.providerTasks(events: events, now: now)
        let compactedCards = PetTaskSummaryBuilder.providerTasks(events: compacted, now: now)
        #expect(fullCards == compactedCards)
        #expect(compactedCards.first?.project.path == "/original")
        #expect(compactedCards.first?.detail == "Finished the change")
    }

    private var retainedHistory: [CodexPetEvent] {
        [event("prompt_submitted", 100, session: "completed"),
         event("stopped", 110, session: "completed"),
         event("tool_failed", 120, session: "completed"),
         event("prompt_submitted", 100, session: "established"),
         event("tool_succeeded", 125, session: "established"),
         event("prompt_submitted", 90, session: "resumed"),
         event("stopped", 100, session: "resumed"),
         event("prompt_submitted", 110, session: "resumed", turn: "turn-b"),
         event("permission_requested", 120, session: "resumed", turn: "turn-b", tool: "pending"),
         event("tool_succeeded", 125, session: "resumed", turn: "turn-b", tool: "other")]
        + (0..<5_000).map { event("tool_started", 130 + Double($0) / 1_000, session: "noisy") }
    }

    @Test("production-capacity compaction preserves terminals, running evidence, and prior turns")
    func compactedReplayEquivalent() {
        let history = retainedHistory
        let now = Date(timeIntervalSince1970: 180)
        let compacted = CodexPetEventLog.compactedEvents(history, now: now, retentionWindow: 86_400, maximumCount: 4_096)
        #expect(compacted.count <= 4_096)
        #expect(compacted.count == 4)
        #expect(CodexPetEventLog.snapshot(events: history, now: now) == CodexPetEventLog.snapshot(events: compacted, now: now))
        let callbacks = [event("tool_failed", 181, session: "resumed", turn: "turn-a"),
            event("tool_succeeded", 182, session: "resumed", turn: "turn-b", tool: "pending"),
            event("permission_requested", 183, session: "completed")]
        let again = CodexPetEventLog.compactedEvents(compacted + callbacks, now: Date(timeIntervalSince1970: 184),
            retentionWindow: 86_400, maximumCount: 4_096)
        #expect(CodexPetEventLog.snapshot(events: history + callbacks, now: Date(timeIntervalSince1970: 184))
            == CodexPetEventLog.snapshot(events: again, now: Date(timeIntervalSince1970: 184)))
    }

    @Test("Python rotation checkpoints replay identically in Swift, including a second rotation")
    func pythonRotationReplayEquivalent() throws {
        let history = retainedHistory
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PetBarRotation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("events.jsonl")
        let bytes = try history.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }.joined(separator: "\n") + "\n"
        try bytes.write(to: input, atomically: true, encoding: .utf8)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let script = root.appendingPathComponent(".codex/hooks/codex_pet_event.py")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-c", """
        import importlib.util, pathlib, sys
        spec = importlib.util.spec_from_file_location('pet_hook', sys.argv[1])
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        data = pathlib.Path(sys.argv[2]).read_bytes()
        retained = module.retained_rotation_bytes(b'', data, 4096, 180)
        retained = module.retained_rotation_bytes(retained, b'', 4096, 180)
        sys.stdout.buffer.write(retained)
        """, script.path, input.path]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let retained = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(retained.count <= 4_096)
        let rotated = String(decoding: retained, as: UTF8.self).split(separator: "\n").compactMap { CodexPetEvent(jsonLine: String($0)) }
        #expect(rotated.count == 4)
        let callbacks = [event("tool_failed", 181, session: "resumed", turn: "turn-a"),
            event("tool_succeeded", 182, session: "resumed", turn: "turn-b", tool: "pending")]
        for additional in [[], callbacks] {
            #expect(CodexPetEventLog.snapshot(events: history + additional, now: Date(timeIntervalSince1970: 183))
                == CodexPetEventLog.snapshot(events: rotated + additional, now: Date(timeIntervalSince1970: 183)))
        }
    }

    @Test("old rollout completion cannot hide a newly resumed hook turn")
    func staleCompletionPreservesFreshTurn() {
        let hooks = CodexPetEventLog.snapshot(events: [CodexPetEvent(kind: "prompt_submitted", timestamp: 200,
            sessionID: "resumed", turnID: "new")], now: Date(timeIntervalSince1970: 201))
        let merged = CodexPetActivityReconciler.merging(snapshot: hooks, runningCodexScopes: [],
            completedCodexScopes: [CodexRolloutActivityScope(sessionID: "resumed",
                modificationDate: Date(timeIntervalSince1970: 205),
                marker: .init(state: .completed, turnID: "old", timestamp: 190))])
        #expect(merged.activeSessionIDs == ["resumed"])
        #expect(merged.activeScopes.first?.activity == .running)
    }

    @Test("a newer callback cannot defeat rollout completion without new-turn evidence")
    func delayedCallbackDoesNotReopenCompletedScan() {
        for turnID in [String?.none, .some("old")] {
            let completed = [CodexRolloutActivityScope(sessionID: "session",
                marker: .init(state: .completed, turnID: turnID, timestamp: 110))]
            let events = [CodexPetEvent(kind: "prompt_submitted", timestamp: 100,
                    sessionID: "session", turnID: turnID),
                CodexPetEvent(kind: "tool_started", timestamp: 120, sessionID: "session", turnID: turnID)]
            for retained in [events, CodexPetEventLog.compactedEvents(events,
                now: Date(timeIntervalSince1970: 121), retentionWindow: 1000, maximumCount: 1)] {
                let snapshot = CodexPetEventLog.snapshot(events: retained, now: Date(timeIntervalSince1970: 121))
                let reconciled = CodexPetActivityReconciler.merging(snapshot: snapshot,
                    runningCodexScopes: [], completedCodexScopes: completed)
                #expect(reconciled.activeScopes.isEmpty)
                #expect(reconciled.activeSessionIDs.isEmpty)
            }
        }
    }

    @Test("resumed and unindexed children have the same status as menu flags")
    func flagsAndCardsAgree() {
        let completed = [CodexRolloutActivityScope(sessionID: "parent")]
        let merged = CodexPetActivityReconciler.merging(snapshot: .init(activity: nil, activeSessionIDs: [], activeScopeCount: 0),
            runningCodexScopes: [.init(sessionID: "resumed"), .init(sessionID: "child", parentSessionID: "parent", workspace: "/project")],
            completedCodexScopes: completed)
        let staleCard = PetTaskSummary(sourceID: "resumed", provider: .codex, title: "Resumed work", detail: "Old completion",
            status: .completed, project: .other, updatedAt: Date(timeIntervalSince1970: 100))
        let cards = PetTaskSummaryBuilder.reconciling(tasks: [staleCard], snapshot: merged,
            completedCodexScopes: completed, now: Date(timeIntervalSince1970: 200))
        #expect(cards.count == 2)
        #expect(cards.allSatisfy { $0.status == .running })
        #expect(cards.first { $0.sourceID == "child" }?.navigationSourceID == "parent")
        #expect(cards.first { $0.sourceID == "child" }?.project.path == "/project")
    }
}

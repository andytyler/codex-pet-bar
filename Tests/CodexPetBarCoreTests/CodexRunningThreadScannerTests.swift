import Foundation
import Testing
@testable import CodexPetBarCore

@Suite("Codex running thread scanner")
struct CodexRunningThreadScannerTests {
    @Test("direct scan finds unindexed parents and spawned children")
    func directScanFindsParentsAndSpawnedChildren() throws {
        let root = try TemporarySessionDirectory()
        let now = try may25AtNoon()
        try root.createRollout(
            name: "rollout-2026-05-25T10-00-00-parent.jsonl",
            contents: topLevelLog(id: "parent", workspace: "/tmp/parent", state: runningLog),
            modifiedAt: now.addingTimeInterval(-20)
        )
        try root.createRollout(
            name: "rollout-2026-05-25T10-01-00-child.jsonl",
            contents: childLog(
                id: "child",
                parentID: "parent",
                workspace: "/tmp/parent",
                state: runningLog
            ),
            modifiedAt: now.addingTimeInterval(-10)
        )

        let scan = CodexRunningThreadScanner.activityScan(
            in: root.url,
            now: now,
            staleAfter: 600
        )

        #expect(scan.runningThreadIDs == ["child", "parent"])
        #expect(scan.runningScopes.first?.parentSessionID == "parent")
        #expect(scan.runningScopes.first?.workspace == "/tmp/parent")
        #expect(scan.completedScopes.isEmpty)
    }

    @Test("direct scan finds a resumed parent in its original old day folder")
    func directScanFindsResumedParentInOldFolder() throws {
        let root = try TemporarySessionDirectory()
        let now = try may25AtNoon()
        try root.createRollout(
            name: "rollout-2025-01-02T10-00-00-resumed.jsonl",
            contents: topLevelLog(id: "resumed", workspace: "/tmp/resumed", state: runningLog),
            modifiedAt: now.addingTimeInterval(-5),
            dayPath: "2025/01/02"
        )

        let scan = CodexRunningThreadScanner.activityScan(
            in: root.url,
            now: now,
            staleAfter: 60
        )

        #expect(scan.runningThreadIDs == ["resumed"])
        #expect(scan.runningScopes.first?.workspace == "/tmp/resumed")
    }

    @Test("direct scan reports child completion and excludes internal guardians")
    func directScanReportsChildCompletionAndExcludesGuardians() throws {
        let root = try TemporarySessionDirectory()
        let now = try may25AtNoon()
        try root.createRollout(
            name: "rollout-2026-05-25T10-00-00-child.jsonl",
            contents: childLog(
                id: "child",
                parentID: "parent",
                workspace: "/tmp/project",
                state: completedLog
            ),
            modifiedAt: now.addingTimeInterval(-10)
        )
        try root.createRollout(
            name: "rollout-2026-05-25T10-01-00-guardian.jsonl",
            contents: guardianLog(id: "guardian", state: runningLog),
            modifiedAt: now.addingTimeInterval(-5)
        )

        let scan = CodexRunningThreadScanner.activityScan(
            in: root.url,
            now: now,
            staleAfter: 600
        )

        #expect(scan.runningScopes.isEmpty)
        #expect(scan.completedThreadIDs == ["child"])
        #expect(scan.completedScopes.first?.parentSessionID == "parent")
    }

    @Test("newest resumed rollout state wins for a repeated session id")
    func newestResumedRolloutStateWins() throws {
        let root = try TemporarySessionDirectory()
        let now = try may25AtNoon()
        try root.createRollout(
            name: "rollout-2025-01-02T10-00-00-same.jsonl",
            contents: topLevelLog(id: "same", state: completedLog),
            modifiedAt: now.addingTimeInterval(-20),
            dayPath: "2025/01/02"
        )
        try root.createRollout(
            name: "rollout-2026-05-25T10-00-00-same.jsonl",
            contents: topLevelLog(id: "same", state: runningLog),
            modifiedAt: now.addingTimeInterval(-5)
        )

        let scan = CodexRunningThreadScanner.activityScan(
            in: root.url,
            now: now,
            staleAfter: 60
        )

        #expect(scan.runningThreadIDs == ["same"])
        #expect(scan.completedScopes.isEmpty)
    }

    @Test("completion tombstone outlives the running lease and clears hook state")
    func completionTombstoneOutlivesRunningLease() throws {
        let root = try TemporarySessionDirectory()
        let now = try may25AtNoon()
        let completedAt = now.addingTimeInterval(-(61 * 60))
        try root.createRollout(
            name: "rollout-2026-05-25T10-00-00-finished.jsonl",
            contents: topLevelLog(id: "finished", state: """
            {"timestamp":\(completedAt.timeIntervalSince1970),"type":"event_msg","payload":{"type":"task_complete","turn_id":"finished-turn"}}
            """),
            modifiedAt: completedAt
        )

        let scan = CodexRunningThreadScanner.activityScan(
            in: root.url,
            now: now,
            staleAfter: 60 * 60,
            retainedCompletionThreadIDs: ["finished"]
        )
        let hookSnapshot = CodexPetEventLog.snapshot(
            events: [
                CodexPetEvent(
                    kind: "tool_started",
                    timestamp: completedAt.timeIntervalSince1970 - 30,
                    provider: .codex,
                    sessionID: "finished",
                    turnID: "finished-turn"
                ),
            ],
            now: now
        )
        let reconciled = CodexPetActivityReconciler.merging(
            snapshot: hookSnapshot,
            runningCodexScopes: scan.runningScopes,
            completedCodexScopes: scan.completedScopes
        )

        #expect(scan.completedThreadIDs == ["finished"])
        #expect(reconciled.activeScopes.isEmpty)
        #expect(reconciled.activeSessionIDs.isEmpty)
    }

    @Test("newest marker-free duplicate does not hide an older valid rollout")
    func newestUnknownDuplicateDoesNotHideValidRollout() throws {
        let root = try TemporarySessionDirectory()
        let now = try may25AtNoon()
        try root.createRollout(
            name: "rollout-2026-05-25T10-00-00-valid.jsonl",
            contents: topLevelLog(id: "same", state: runningLog),
            modifiedAt: now.addingTimeInterval(-10)
        )
        try root.createRollout(
            name: "rollout-2026-05-25T10-01-00-bootstrap.jsonl",
            contents: topLevelLog(id: "same", state: #"{"type":"unrelated"}"#),
            modifiedAt: now.addingTimeInterval(-5)
        )

        let scan = CodexRunningThreadScanner.activityScan(
            in: root.url,
            now: now,
            staleAfter: 60
        )

        #expect(scan.runningThreadIDs == ["same"])
    }

    @Test("counts only fresh running rollout logs")
    func countsOnlyFreshRunningRolloutLogs() throws {
        let root = try TemporarySessionDirectory()
        let now = try may25AtNoon()
        try root.createRollout(
            name: "rollout-2026-05-25T10-00-00-thread-running.jsonl",
            contents: runningLog,
            modifiedAt: now.addingTimeInterval(-30)
        )
        try root.createRollout(
            name: "rollout-2026-05-25T10-00-00-thread-complete.jsonl",
            contents: completedLog,
            modifiedAt: now.addingTimeInterval(-20)
        )
        try root.createRollout(
            name: "rollout-2026-05-25T10-00-00-thread-stale.jsonl",
            contents: runningLog,
            modifiedAt: now.addingTimeInterval(-700)
        )

        let count = CodexRunningThreadScanner.runningThreadCount(
            in: root.url,
            now: now,
            staleAfter: 600,
            limit: 80
        )

        #expect(count == 1)
    }

    @Test("returns newest running rollout logs up to the scan limit")
    func returnsNewestRunningRolloutLogsUpToScanLimit() throws {
        let root = try TemporarySessionDirectory()
        let now = try may25AtNoon()
        try root.createRollout(
            name: "rollout-2026-05-25T10-00-00-thread-new.jsonl",
            contents: runningLog,
            modifiedAt: now.addingTimeInterval(-10)
        )
        try root.createRollout(
            name: "rollout-2026-05-25T10-00-00-thread-old.jsonl",
            contents: runningLog,
            modifiedAt: now.addingTimeInterval(-20)
        )

        let urls = CodexRunningThreadScanner.runningThreadLogURLs(
            in: root.url,
            now: now,
            staleAfter: 600,
            limit: 1
        )

        #expect(urls.map(\.lastPathComponent) == ["rollout-2026-05-25T10-00-00-thread-new.jsonl"])
    }

    @Test("scan limit applies after completed rollout logs are filtered")
    func scanLimitAppliesAfterCompletedRolloutLogsAreFiltered() throws {
        let root = try TemporarySessionDirectory()
        let now = try may25AtNoon()
        try root.createRollout(
            name: "rollout-2026-05-25T10-00-00-thread-complete-newest.jsonl",
            contents: completedLog,
            modifiedAt: now.addingTimeInterval(-10)
        )
        try root.createRollout(
            name: "rollout-2026-05-25T10-00-00-thread-complete-middle.jsonl",
            contents: completedLog,
            modifiedAt: now.addingTimeInterval(-20)
        )
        try root.createRollout(
            name: "rollout-2026-05-25T10-00-00-thread-running-older.jsonl",
            contents: runningLog,
            modifiedAt: now.addingTimeInterval(-30)
        )

        let urls = CodexRunningThreadScanner.runningThreadLogURLs(
            in: root.url,
            now: now,
            staleAfter: 600,
            limit: 1
        )

        #expect(urls.map(\.lastPathComponent) == ["rollout-2026-05-25T10-00-00-thread-running-older.jsonl"])
    }

    @Test("negative scan limit returns no rollout logs")
    func negativeScanLimitReturnsNoRolloutLogs() throws {
        let root = try TemporarySessionDirectory()
        let now = try may25AtNoon()
        try root.createRollout(
            name: "rollout-2026-05-25T10-00-00-thread-running.jsonl",
            contents: runningLog,
            modifiedAt: now.addingTimeInterval(-10)
        )

        let urls = CodexRunningThreadScanner.runningThreadLogURLs(
            in: root.url,
            now: now,
            staleAfter: 600,
            limit: -1
        )

        #expect(urls.isEmpty)
    }

    @Test("targeted scan uses recent thread ids instead of unrelated running logs")
    func targetedScanUsesRecentThreadIDsInsteadOfUnrelatedRunningLogs() throws {
        let root = try TemporarySessionDirectory()
        let now = try may25AtNoon()
        let threadID = "019e5fc3-d422-7be0-a5e2-969c55d4a723"
        try root.createRollout(
            name: "rollout-2026-05-25T10-00-00-\(threadID).jsonl",
            contents: runningLog,
            modifiedAt: now.addingTimeInterval(-10)
        )
        try root.createRollout(
            name: "rollout-2026-05-25T10-00-00-unrelated.jsonl",
            contents: runningLog,
            modifiedAt: now.addingTimeInterval(-5)
        )

        let urls = CodexRunningThreadScanner.runningThreadLogURLs(
            forThreadIDs: [threadID],
            in: root.url,
            now: now,
            staleAfter: 600,
            limit: 80
        )

        #expect(urls.map(\.lastPathComponent) == ["rollout-2026-05-25T10-00-00-\(threadID).jsonl"])
    }

    @Test("targeted scan matches thread ids exactly")
    func targetedScanMatchesThreadIDsExactly() throws {
        let root = try TemporarySessionDirectory()
        let now = try may25AtNoon()
        let threadID = "thread-1"
        try root.createRollout(
            name: "rollout-2026-05-25T10-00-00-thread-10.jsonl",
            contents: runningLog,
            modifiedAt: now.addingTimeInterval(-5)
        )
        try root.createRollout(
            name: "rollout-2026-05-25T10-00-00-\(threadID).jsonl",
            contents: runningLog,
            modifiedAt: now.addingTimeInterval(-10)
        )

        let urls = CodexRunningThreadScanner.runningThreadLogURLs(
            forThreadIDs: [threadID],
            in: root.url,
            now: now,
            staleAfter: 600,
            limit: 80
        )

        #expect(urls.map(\.lastPathComponent) == ["rollout-2026-05-25T10-00-00-\(threadID).jsonl"])
    }

    @Test("returns supplied running thread ids newest first without subagents")
    func returnsTopLevelRunningThreadIDsNewestFirst() throws {
        let root = try TemporarySessionDirectory()
        let now = try may25AtNoon()
        let olderThreadID = "019e5fc3-d422-7be0-a5e2-969c55d4a723"
        let newerThreadID = "019e5fc4-a111-7be0-a5e2-969c55d4a724"
        let subagentThreadID = "019e5fc5-b222-7be0-a5e2-969c55d4a725"
        try root.createRollout(
            name: "rollout-2026-05-25T10-00-00-\(olderThreadID).jsonl",
            contents: runningLog,
            modifiedAt: now.addingTimeInterval(-30)
        )
        try root.createRollout(
            name: "rollout-2026-05-25T10-01-00-\(newerThreadID).jsonl",
            contents: runningLog,
            modifiedAt: now.addingTimeInterval(-10)
        )
        try root.createRollout(
            name: "rollout-2026-05-25T10-02-00-\(subagentThreadID).jsonl",
            contents: runningLog,
            modifiedAt: now.addingTimeInterval(-5)
        )

        let ids = CodexRunningThreadScanner.runningThreadIDs(
            forThreadIDs: [olderThreadID, newerThreadID],
            in: root.url,
            now: now,
            staleAfter: 600
        )

        #expect(ids == [newerThreadID, olderThreadID])
        #expect(!ids.contains(subagentThreadID))
    }

    @Test("running thread id parsing uses exact suffixes and unique ids")
    func runningThreadIDsUseExactUniqueSuffixes() throws {
        let root = try TemporarySessionDirectory()
        let now = try may25AtNoon()
        let threadID = "thread-1"
        try root.createRollout(
            name: "rollout-2026-05-25T10-00-00-thread-10.jsonl",
            contents: runningLog,
            modifiedAt: now.addingTimeInterval(-5)
        )
        try root.createRollout(
            name: "rollout-2026-05-25T10-00-00-\(threadID).jsonl",
            contents: runningLog,
            modifiedAt: now.addingTimeInterval(-10)
        )
        try root.createRollout(
            name: "rollout-2026-05-25T09-59-00-\(threadID).jsonl",
            contents: runningLog,
            modifiedAt: now.addingTimeInterval(-20)
        )

        let ids = CodexRunningThreadScanner.runningThreadIDs(
            forThreadIDs: [threadID],
            in: root.url,
            now: now,
            staleAfter: 600,
            limit: 1
        )

        #expect(ids == [threadID])
    }

    @Test("nonpositive running thread id limits return no ids")
    func nonpositiveRunningThreadIDLimitReturnsNoIDs() throws {
        let root = try TemporarySessionDirectory()
        let now = try may25AtNoon()
        try root.createRollout(
            name: "rollout-2026-05-25T10-00-00-thread-1.jsonl",
            contents: runningLog,
            modifiedAt: now.addingTimeInterval(-5)
        )

        let ids = CodexRunningThreadScanner.runningThreadIDs(
            forThreadIDs: ["thread-1"],
            in: root.url,
            now: now,
            limit: 0
        )

        #expect(ids.isEmpty)
    }

    @Test("activity scan distinguishes explicit completion from unknown logs")
    func activityScanDistinguishesCompletionFromUnknown() throws {
        let root = try TemporarySessionDirectory()
        let now = try may25AtNoon()
        try root.createRollout(
            name: "rollout-2026-05-25T10-00-00-running.jsonl",
            contents: runningLog,
            modifiedAt: now.addingTimeInterval(-10)
        )
        try root.createRollout(
            name: "rollout-2026-05-25T10-00-00-completed.jsonl",
            contents: completedLog,
            modifiedAt: now.addingTimeInterval(-20)
        )
        try root.createRollout(
            name: "rollout-2026-05-25T10-00-00-unknown.jsonl",
            contents: #"{"type":"unrelated"}"#,
            modifiedAt: now.addingTimeInterval(-30)
        )

        let scan = CodexRunningThreadScanner.activityScan(
            forThreadIDs: ["running", "completed", "unknown"],
            in: root.url,
            now: now,
            staleAfter: 600
        )

        #expect(scan.runningThreadIDs == ["running"])
        #expect(scan.completedThreadIDs == ["completed"])
    }

    @Test("activity scan retains stale completion without treating stale work as running")
    func activityScanRetainsCompletionBeyondLivenessWindow() throws {
        let root = try TemporarySessionDirectory()
        let now = try may25AtNoon()
        try root.createRollout(
            name: "rollout-2026-05-25T10-00-00-stale-running.jsonl",
            contents: runningLog,
            modifiedAt: now.addingTimeInterval(-700)
        )
        try root.createRollout(
            name: "rollout-2026-05-25T10-00-00-stale-completed.jsonl",
            contents: completedLog,
            modifiedAt: now.addingTimeInterval(-700)
        )

        let scan = CodexRunningThreadScanner.activityScan(
            forThreadIDs: ["stale-running", "stale-completed"],
            in: root.url,
            now: now,
            staleAfter: 600
        )

        #expect(scan.runningThreadIDs.isEmpty)
        #expect(scan.completedThreadIDs == ["stale-completed"])
    }
}

private let runningLog = """
{"timestamp":"2026-05-25T10:00:00.000Z","type":"event_msg","payload":{"type":"task_started"}}
"""

private let completedLog = """
{"timestamp":"2026-05-25T10:00:00.000Z","type":"event_msg","payload":{"type":"task_started"}}
{"timestamp":"2026-05-25T10:01:00.000Z","type":"event_msg","payload":{"type":"task_complete"}}
"""

private func topLevelLog(id: String, workspace: String? = nil, state: String) -> String {
    let cwd = workspace.map { ",\"cwd\":\"\($0)\"" } ?? ""
    return """
    {"type":"session_meta","payload":{"id":"\(id)","source":"vscode"\(cwd)}}
    \(state)
    """
}

private func childLog(id: String, parentID: String, workspace: String, state: String) -> String {
    """
    {"type":"session_meta","payload":{"id":"\(id)","cwd":"\(workspace)","source":{"subagent":{"thread_spawn":{"parent_thread_id":"\(parentID)","depth":1}}}}}
    \(state)
    """
}

private func guardianLog(id: String, state: String) -> String {
    """
    {"type":"session_meta","payload":{"id":"\(id)","source":{"subagent":{"other":"guardian"}}}}
    \(state)
    """
}

private func may25AtNoon() throws -> Date {
    let date = ISO8601DateFormatter.codexSessionIndex.date(from: "2026-05-25T12:00:00.000Z")
    return try #require(date)
}

private struct TemporarySessionDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexRunningThreadScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func createRollout(
        name: String,
        contents: String,
        modifiedAt: Date,
        dayPath: String = "2026/05/25"
    ) throws {
        let directory = url.appendingPathComponent(dayPath, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(name)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: fileURL.path)
    }
}

import Foundation
import Testing
@testable import CodexPetBarCore

@Suite("Codex completion markers")
struct CodexCompletionMarkerTests {
    @Test("successful and cancelled terminals preserve existing completed state")
    func terminalOutcomes() throws {
        let success = try #require(CodexRunningThreadLog.marker(jsonLines:
            #"{"timestamp":"2026-05-25T10:01:00.123Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-a","id":"fallback"}}"#))
        let cancelled = try #require(CodexRunningThreadLog.marker(jsonLines:
            #"{"timestamp":"2026-05-25T10:01:00Z","type":"event_msg","payload":{"type":"turn_aborted","turn_id":"turn-a"}}"#))
        #expect(success.state == .completed)
        #expect(success.completionOutcome == .success)
        #expect(success.turnID == "turn-a")
        #expect(success.terminalIdentity == "turn:turn-a")
        #expect(success.timestamp != nil)
        #expect(cancelled.state == .completed)
        #expect(cancelled.completionOutcome == .cancelled)
        #expect(cancelled.timestamp != nil)
    }

    @Test("completion id is a fallback and activity has no terminal identity")
    func markerIdentity() throws {
        let complete = try #require(CodexRunningThreadLog.marker(jsonLines:
            #"{"timestamp":120.5,"type":"event_msg","payload":{"type":"task_complete","id":"turn-b"}}"#))
        let resumed = try #require(CodexRunningThreadLog.marker(jsonLines:
            """
            {"timestamp":120.5,"type":"event_msg","payload":{"type":"task_complete","id":"turn-a"}}
            {"timestamp":130.5,"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-b"}}
            """))
        #expect(complete.turnID == "turn-b")
        #expect(complete.timestamp == 120.5)
        #expect(resumed.state == .running)
        #expect(resumed.turnID == "turn-b")
        #expect(resumed.completionOutcome == nil)
        #expect(resumed.terminalIdentity == nil)
    }

    @Test("bounded tail expansion returns marker metadata once")
    func boundedReaderRetainsMetadata() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("rollout.jsonl")
        let content = #"{"timestamp":120.5,"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-a"}}"#
            + "\n" + #"{"type":"unrelated","padding":"\#(String(repeating: "x", count: 20_000))"}"# + "\n"
        try content.write(to: url, atomically: true, encoding: .utf8)
        let marker = try CodexRunningThreadLog.marker(in: url, tailByteLimit: 4096, maximumTailByteLimit: 32768)
        #expect(marker?.completionOutcome == .success)
        #expect(marker?.terminalIdentity == "turn:turn-a")
        #expect(try CodexRunningThreadLog.marker(in: url, tailByteLimit: 4096, maximumTailByteLimit: 4096) == nil)
    }

    @Test("scanner carries actual terminal metadata independent of modification time")
    func scannerPreservesMarker() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let day = directory.appendingPathComponent("2026/05/25")
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = day.appendingPathComponent("rollout-2026-05-25T10-00-00-session.jsonl")
        try """
        {"type":"session_meta","payload":{"id":"session","source":"vscode"}}
        {"timestamp":"2026-05-25T10:01:00.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-a"}}
        """.write(to: url, atomically: true, encoding: .utf8)
        let now = try #require(ISO8601DateFormatter().date(from: "2026-05-25T12:00:00Z"))
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-10)], ofItemAtPath: url.path)
        let first = CodexRunningThreadScanner.activityScan(in: directory, now: now)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
        let second = CodexRunningThreadScanner.activityScan(in: directory, now: now)
        #expect(first.completedThreadIDs == ["session"])
        #expect(first.completedScopes.first?.marker?.completionOutcome == .success)
        #expect(first.completedScopes.first?.marker == second.completedScopes.first?.marker)
        #expect(first.completedScopes.first?.modificationDate != second.completedScopes.first?.modificationDate)
    }
}

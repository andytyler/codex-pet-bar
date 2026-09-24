import Foundation
import Testing
@testable import CodexPetBarCore

@Suite("Codex running thread logs")
struct CodexRunningThreadLogTests {
    @Test("a user turn without later completion is running")
    func userTurnWithoutLaterCompletionIsRunning() {
        let log = """
        {"timestamp":"2026-05-18T20:00:00.000Z","type":"event_msg","payload":{"type":"task_complete"}}
        {"timestamp":"2026-05-18T20:01:00.000Z","type":"event_msg","payload":{"type":"user_message","message":"go"}}
        {"timestamp":"2026-05-18T20:01:01.000Z","type":"response_item","payload":{"type":"function_call","name":"exec_command"}}
        """

        #expect(CodexRunningThreadLog.isRunning(jsonLines: log))
    }

    @Test("task completion after a turn is not running")
    func taskCompletionAfterTurnIsNotRunning() {
        let log = """
        {"timestamp":"2026-05-18T20:01:00.000Z","type":"event_msg","payload":{"type":"user_message","message":"go"}}
        {"timestamp":"2026-05-18T20:01:01.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"done"}]}}
        {"timestamp":"2026-05-18T20:01:02.000Z","type":"event_msg","payload":{"type":"task_complete"}}
        """

        #expect(!CodexRunningThreadLog.isRunning(jsonLines: log))
        #expect(CodexRunningThreadLog.state(jsonLines: log) == .completed)
    }

    @Test("assistant activity after completion starts a running state")
    func assistantActivityAfterCompletionStartsRunningState() {
        let log = """
        {"timestamp":"2026-05-18T20:00:00.000Z","type":"event_msg","payload":{"type":"task_complete"}}
        {"timestamp":"2026-05-18T20:01:00.000Z","type":"event_msg","payload":{"type":"agent_message","message":"working"}}
        """

        #expect(CodexRunningThreadLog.isRunning(jsonLines: log))
    }

    @Test("task started after completion is running")
    func taskStartedAfterCompletionIsRunning() {
        let log = """
        {"timestamp":"2026-05-18T20:00:00.000Z","type":"event_msg","payload":{"type":"task_complete"}}
        {"timestamp":"2026-05-18T20:01:00.000Z","type":"event_msg","payload":{"type":"task_started"}}
        """

        #expect(CodexRunningThreadLog.isRunning(jsonLines: log))
    }

    @Test("tool search calls after completion are running")
    func toolSearchCallsAfterCompletionAreRunning() {
        let log = """
        {"timestamp":"2026-05-18T20:00:00.000Z","type":"event_msg","payload":{"type":"task_complete"}}
        {"timestamp":"2026-05-18T20:01:00.000Z","type":"response_item","payload":{"type":"tool_search_call","query":"Codex MCP"}}
        """

        #expect(CodexRunningThreadLog.isRunning(jsonLines: log))
    }

    @Test("task completion after current rollout tool activity is not running")
    func taskCompletionAfterCurrentRolloutToolActivityIsNotRunning() {
        let log = """
        {"timestamp":"2026-05-18T20:01:00.000Z","type":"event_msg","payload":{"type":"task_started"}}
        {"timestamp":"2026-05-18T20:01:01.000Z","type":"response_item","payload":{"type":"tool_search_call","query":"Codex MCP"}}
        {"timestamp":"2026-05-18T20:01:02.000Z","type":"event_msg","payload":{"type":"task_complete"}}
        """

        #expect(!CodexRunningThreadLog.isRunning(jsonLines: log))
    }

    @Test("an aborted turn is terminal")
    func abortedTurnIsTerminal() {
        let log = """
        {"timestamp":"2026-05-18T20:01:00.000Z","type":"event_msg","payload":{"type":"task_started"}}
        {"timestamp":"2026-05-18T20:01:01.000Z","type":"response_item","payload":{"type":"function_call","name":"exec_command"}}
        {"timestamp":"2026-05-18T20:01:02.000Z","type":"event_msg","payload":{"type":"turn_aborted"}}
        """

        #expect(CodexRunningThreadLog.state(jsonLines: log) == .completed)
    }

    @Test("file scanning expands past an oversized trailing record")
    func fileScanningExpandsPastOversizedTrailingRecord() throws {
        let oversizedRecord = #"{"type":"unrelated","payload":"\#(String(repeating: "x", count: 600_000))"}"#
        let url = try temporaryRunningThreadLog(contents: """
        {"timestamp":"2026-05-18T20:01:00.000Z","type":"event_msg","payload":{"type":"task_started"}}
        \(oversizedRecord)
        """)

        #expect(try CodexRunningThreadLog.isRunning(
            in: url,
            tailByteLimit: 262_144,
            maximumTailByteLimit: 1_048_576
        ))
    }

    @Test("file scanning finds completion before an oversized trailing record")
    func fileScanningFindsCompletionBeforeOversizedTrailingRecord() throws {
        let oversizedRecord = #"{"type":"unrelated","payload":"\#(String(repeating: "x", count: 600_000))"}"#
        let url = try temporaryRunningThreadLog(contents: """
        {"timestamp":"2026-05-18T20:01:00.000Z","type":"event_msg","payload":{"type":"task_started"}}
        {"timestamp":"2026-05-18T20:01:01.000Z","type":"event_msg","payload":{"type":"task_complete"}}
        \(oversizedRecord)
        """)

        #expect(try !CodexRunningThreadLog.isRunning(
            in: url,
            tailByteLimit: 262_144,
            maximumTailByteLimit: 1_048_576
        ))
    }

    @Test("file scanning respects invalid and bounded limits")
    func fileScanningRespectsInvalidAndBoundedLimits() throws {
        let oversizedRecord = #"{"type":"unrelated","payload":"\#(String(repeating: "x", count: 600_000))"}"#
        let url = try temporaryRunningThreadLog(contents: """
        {"timestamp":"2026-05-18T20:01:00.000Z","type":"event_msg","payload":{"type":"task_started"}}
        \(oversizedRecord)
        """)

        #expect(try !CodexRunningThreadLog.isRunning(
            in: url,
            tailByteLimit: 0,
            maximumTailByteLimit: 1_048_576
        ))
        #expect(try !CodexRunningThreadLog.isRunning(
            in: url,
            tailByteLimit: 262_144,
            maximumTailByteLimit: 262_144
        ))
    }

    @Test("an exact tail line boundary retains its first complete marker")
    func exactTailLineBoundaryRetainsFirstCompleteMarker() throws {
        let suffix = """
        {"timestamp":"2026-05-18T20:01:00.000Z","type":"event_msg","payload":{"type":"task_started"}}
        {"type":"unrelated"}
        """ + "\n"
        let contents = "{\"type\":\"older\"}\n" + suffix
        let url = try temporaryRunningThreadLog(contents: contents, appendingNewline: false)
        let exactTailByteCount = suffix.utf8.count

        #expect(try CodexRunningThreadLog.isRunning(
            in: url,
            tailByteLimit: exactTailByteCount,
            maximumTailByteLimit: exactTailByteCount
        ))
    }
}

private func temporaryRunningThreadLog(
    contents: String,
    appendingNewline: Bool = true
) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("CodexRunningThreadLogTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("rollout.jsonl")
    let fileContents = appendingNewline ? contents + "\n" : contents
    try fileContents.write(to: url, atomically: true, encoding: .utf8)
    return url
}

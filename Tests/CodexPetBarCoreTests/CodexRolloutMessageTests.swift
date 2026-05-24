import Foundation
import Testing
@testable import CodexPetBarCore

@Suite("Codex rollout messages")
struct CodexRolloutMessageTests {
    @Test("extracts assistant agent messages from rollout event lines")
    func extractsAssistantAgentMessagesFromRolloutEventLines() throws {
        let line = #"""
        {"timestamp":"2026-05-18T20:35:49.374Z","type":"event_msg","payload":{"type":"agent_message","message":"First line\nsecond   line","phase":"commentary"}}
        """#

        let message = try #require(CodexRolloutMessage(jsonLine: line))

        #expect(message.text == "First line second line")
        #expect(message.timestamp == ISO8601DateFormatter.codexRollout.date(from: "2026-05-18T20:35:49.374Z"))
    }

    @Test("ignores user messages and tool output")
    func ignoresUserMessagesAndToolOutput() throws {
        let userLine = #"""
        {"timestamp":"2026-05-18T20:35:49.374Z","type":"event_msg","payload":{"type":"user_message","message":"secret prompt"}}
        """#
        let toolLine = #"""
        {"timestamp":"2026-05-18T20:35:49.374Z","type":"response_item","payload":{"type":"function_call_output","output":"huge tool output"}}
        """#

        #expect(CodexRolloutMessage(jsonLine: userLine) == nil)
        #expect(CodexRolloutMessage(jsonLine: toolLine) == nil)
    }

    @Test("reader returns complete newly appended messages without mirrored duplicates")
    func readerReturnsCompleteNewlyAppendedMessagesWithoutMirroredDuplicates() throws {
        let root = try TemporaryRolloutDirectory()
        let logURL = root.url.appendingPathComponent("rollout.jsonl")
        try """
        {"timestamp":"2026-05-18T20:35:49.374Z","type":"event_msg","payload":{"type":"agent_message","message":"Hello from Codex","phase":"commentary"}}
        {"timestamp":"2026-05-18T20:35:49.374Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Hello from Codex"}],"phase":"commentary"}}
        {"timestamp":"2026-05-18T20:36:00.000Z","type":"event_msg","payload":{"type":"agent_message","message":"Second
        """.write(to: logURL, atomically: true, encoding: .utf8)
        var offset: UInt64 = 0

        let firstRead = try CodexRolloutMessageLog.readMessages(from: logURL, startingAt: &offset)

        #expect(firstRead.map(\.text) == ["Hello from Codex"])

        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        handle.write(Data(#" message","phase":"final"}}"#.utf8))
        handle.write(Data("\n".utf8))
        try handle.close()

        let secondRead = try CodexRolloutMessageLog.readMessages(from: logURL, startingAt: &offset)

        #expect(secondRead.map(\.text) == ["Second message"])
    }
}

private struct TemporaryRolloutDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexRolloutMessageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

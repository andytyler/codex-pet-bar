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
    }

    @Test("assistant activity after completion starts a running state")
    func assistantActivityAfterCompletionStartsRunningState() {
        let log = """
        {"timestamp":"2026-05-18T20:00:00.000Z","type":"event_msg","payload":{"type":"task_complete"}}
        {"timestamp":"2026-05-18T20:01:00.000Z","type":"event_msg","payload":{"type":"agent_message","message":"working"}}
        """

        #expect(CodexRunningThreadLog.isRunning(jsonLines: log))
    }
}

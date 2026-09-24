import Foundation
import Testing
@testable import CodexPetBarCore

@Suite("Codex state and preferences")
struct CodexStateTests {
    @Test("parses selected custom avatar id from global state")
    func parsesSelectedCustomAvatarID() throws {
        let data = Data(#"{"selected-avatar-id":"custom:goblin"}"#.utf8)

        let selectedPetID = try CodexGlobalState.selectedPetID(from: data)

        #expect(selectedPetID == "goblin")
    }

    @Test("manual pet override wins until follow Codex is enabled")
    func manualOverrideWinsUntilFollowCodexIsEnabled() throws {
        let defaults = try isolatedDefaults()
        let preferences = AppPreferences(defaults: defaults)
        let goblin = PetPackage.fixture(id: "goblin", displayName: "Goblin")
        let tock = PetPackage.fixture(id: "tock", displayName: "Tock")

        preferences.followCodexPet = false
        preferences.selectedPetIDOverride = "tock"

        #expect(PetSelection.resolve(pets: [goblin, tock], preferences: preferences, codexSelectedPetID: "goblin")?.id == "tock")

        preferences.followCodexPet = true

        #expect(PetSelection.resolve(pets: [goblin, tock], preferences: preferences, codexSelectedPetID: "goblin")?.id == "goblin")
    }

    @Test("activity maps to playful pet animation states")
    func activityMapsToAnimationState() {
        #expect(CodexActivity.idle.animationState == .idle)
        #expect(CodexActivity.running.animationState == .running)
        #expect(CodexActivity.reviewing.animationState == .waiting)
        #expect(CodexActivity.listening.animationState == .idle)
        #expect(CodexActivity.failed.animationState == .failed)
    }

    @Test("recent Codex hook events drive activity state")
    func recentCodexHookEventsDriveActivityState() {
        let log = """
        {"event":"prompt_submitted","timestamp":100}
        {"event":"permission_requested","timestamp":110}
        """

        let activity = CodexPetEventLog.activity(
            jsonLines: log,
            now: Date(timeIntervalSince1970: 115),
            activeWindow: 30
        )

        #expect(activity == .reviewing)
    }

    @Test("stopped event from one session does not cancel another active session")
    func stoppedEventFromOneSessionDoesNotCancelAnotherActiveSession() {
        let log = """
        {"event":"tool_started","timestamp":100,"workspace":"/workspace-b","session_id":"session-b"}
        {"event":"stopped","timestamp":110,"workspace":"/workspace-a","session_id":"session-a"}
        """

        let activity = CodexPetEventLog.activity(
            jsonLines: log,
            now: Date(timeIntervalSince1970: 115),
            activeWindow: 30
        )

        #expect(activity == .running)
    }

    @Test("active session activity is prioritized across sessions")
    func activeSessionActivityIsPrioritizedAcrossSessions() {
        let reviewLog = """
        {"event":"permission_requested","timestamp":100,"workspace":"/workspace-a","session_id":"reviewing"}
        {"event":"tool_failed","timestamp":101,"workspace":"/workspace-b","session_id":"failed"}
        {"event":"tool_started","timestamp":102,"workspace":"/workspace-c","session_id":"running"}
        {"event":"session_started","timestamp":103,"workspace":"/workspace-d","session_id":"listening"}
        {"event":"stopped","timestamp":104,"workspace":"/workspace-e","session_id":"idle"}
        """
        let failedLog = """
        {"event":"tool_failed","timestamp":101,"workspace":"/workspace-b","session_id":"failed"}
        {"event":"tool_started","timestamp":102,"workspace":"/workspace-c","session_id":"running"}
        {"event":"session_started","timestamp":103,"workspace":"/workspace-d","session_id":"listening"}
        {"event":"stopped","timestamp":104,"workspace":"/workspace-e","session_id":"idle"}
        """
        let runningLog = """
        {"event":"tool_started","timestamp":102,"workspace":"/workspace-c","session_id":"running"}
        {"event":"session_started","timestamp":103,"workspace":"/workspace-d","session_id":"listening"}
        {"event":"stopped","timestamp":104,"workspace":"/workspace-e","session_id":"idle"}
        """
        let now = Date(timeIntervalSince1970: 105)

        #expect(CodexPetEventLog.activity(jsonLines: reviewLog, now: now, activeWindow: 30) == .reviewing)
        #expect(CodexPetEventLog.activity(jsonLines: failedLog, now: now, activeWindow: 30) == .failed)
        #expect(CodexPetEventLog.activity(jsonLines: runningLog, now: now, activeWindow: 30) == .running)
    }

    @Test("permission request remains reviewing until its matching tool completes")
    func permissionRequestRemainsReviewingUntilMatchingResolution() {
        let pendingLog = """
        {"event":"permission_requested","timestamp":100,"workspace":"/workspace-a","session_id":"session-a","tool_use_id":"bash-1"}
        {"event":"tool_started","timestamp":300,"workspace":"/workspace-a","session_id":"session-a","tool_use_id":"read-1"}
        """
        let resolvedLog = pendingLog + "\n" + """
        {"event":"tool_succeeded","timestamp":304,"workspace":"/workspace-a","session_id":"session-a","tool_use_id":"bash-1"}
        """

        #expect(CodexPetEventLog.activity(jsonLines: pendingLog,
            now: Date(timeIntervalSince1970: 305), activeWindow: 30) == .reviewing)
        #expect(CodexPetEventLog.activity(jsonLines: resolvedLog,
            now: Date(timeIntervalSince1970: 305), activeWindow: 30) == .running)
    }

    @Test("incremental reader returns complete events and preserves approval edge")
    func incrementalReaderReturnsCompleteEventsAndPreservesApprovalEdge() throws {
        let root = try TemporaryPetEventDirectory()
        let logURL = root.url.appendingPathComponent("pet-events.jsonl")
        try """
        {"event":"permission_requested","timestamp":100,"workspace":"/workspace-a","session_id":"session-a","tool_use_id":"bash-1"}
        {"event":"tool_started","timestamp":101,"workspace":"/workspace-a","session_id":"session-a","tool_use_id":"read-1"}
        {"event":"tool_succeeded","timestamp":102
        """.write(to: logURL, atomically: true, encoding: .utf8)
        var offset: UInt64 = 0

        let firstRead = try CodexPetEventLog.readEvents(from: logURL, startingAt: &offset)

        #expect(firstRead.map(\.kind) == ["permission_requested", "tool_started"])
        #expect(
            CodexPetEventLog.activity(
                jsonLines: try String(contentsOf: logURL, encoding: .utf8),
                now: Date(timeIntervalSince1970: 105),
                activeWindow: 30
            ) == .reviewing
        )

        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        handle.write(Data(#","workspace":"/workspace-a","session_id":"session-a","tool_use_id":"bash-1"}"#.utf8))
        handle.write(Data("\n".utf8))
        try handle.close()

        let secondRead = try CodexPetEventLog.readEvents(from: logURL, startingAt: &offset)

        #expect(secondRead.map(\.kind) == ["tool_succeeded"])
        #expect(CodexPetEventLog.snapshot(events: firstRead + secondRead,
            now: Date(timeIntervalSince1970: 105), activeWindow: 30).activity == .running)
    }

    @Test("failed and stale Codex hook events are handled explicitly")
    func failedAndStaleCodexHookEventsAreHandledExplicitly() {
        let failedLog = #"{"event":"tool_failed","timestamp":200}"#
        let staleLog = #"{"event":"tool_started","timestamp":10}"#

        #expect(
            CodexPetEventLog.activity(
                jsonLines: failedLog,
                now: Date(timeIntervalSince1970: 205),
                activeWindow: 30
            ) == .failed
        )
        #expect(
            CodexPetEventLog.activity(
                jsonLines: staleLog,
                now: Date(timeIntervalSince1970: 205),
                activeWindow: 30
            ) == nil
        )
    }

    @Test("menu bar sizes reserve a wider click and animation target")
    func menuBarSizesReserveWiderTarget() {
        #expect(PetSize.small.menuBarLength == 44)
        #expect(PetSize.medium.menuBarLength == 56)
        #expect(PetSize.large.menuBarLength == 102)
    }
}

private func isolatedDefaults() throws -> UserDefaults {
    let suiteName = "CodexPetBarTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private struct TemporaryPetEventDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPetEventTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

private extension PetPackage {
    static func fixture(id: String, displayName: String) -> PetPackage {
        PetPackage(
            id: id,
            displayName: displayName,
            description: "Fixture",
            directoryURL: URL(fileURLWithPath: "/tmp/\(id)", isDirectory: true),
            spritesheetURL: URL(fileURLWithPath: "/tmp/\(id)/spritesheet.webp")
        )
    }
}

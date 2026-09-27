import Foundation
import Testing
@testable import CodexPetBarCore

@Suite("Bounded active Codex identity lookup")
struct CodexTaskSummaryReaderActiveIdentityTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("an active child retains its named parent outside recent history")
    func activeParentOutsideHistoryLimit() throws {
        let fixture = try IndexFixture(lines: [
            line("unrelated-old", title: "Unrelated history", timestamp: 10),
            line("older-parent", title: "The resumed task", timestamp: 20),
            line("history-a", title: "Newer history A", timestamp: 30),
            line("history-b", title: "Newer history B", timestamp: 40),
        ])
        defer { fixture.remove() }
        let child = event("older-parent:child:worker", parent: "older-parent")

        let tasks = fixture.read(events: [child], now: now, configuration: .init(recentThreadLimit: 2))

        #expect(Set(tasks.map(\.sourceID)) == ["older-parent", "older-parent:child:worker", "history-a", "history-b"])
        #expect(tasks.first { $0.sourceID == "older-parent" }?.title == "The resumed task")
        #expect(tasks.first { $0.sourceID == "older-parent:child:worker" }?.navigationSourceID == "older-parent")
        #expect(tasks.first { $0.sourceID == "older-parent:child:worker" }?.status == .running)
        #expect(tasks.filter { $0.sourceID.hasPrefix("history-") }.count == 2)
    }

    @Test("a resumed indexed task gets its title without a duplicate fallback card")
    func activeSourceOutsideHistoryLimit() throws {
        let fixture = try IndexFixture(lines: [
            line("resumed", title: "Named work", timestamp: 10),
            line("history", title: "Newer history", timestamp: 20),
        ])
        defer { fixture.remove() }

        let tasks = fixture.read(events: [event("resumed")], now: now,
                                 configuration: .init(recentThreadLimit: 1, providerTaskLimit: 0))

        #expect(tasks.count == 2)
        let resumed = try #require(tasks.first { $0.sourceID == "resumed" })
        #expect(resumed.title == "Named work")
        #expect(resumed.status == .running)
        #expect(resumed.project.name == "example-project")
        #expect(resumed.deepLinkURL == CodexThreadDeepLink.url(forThreadID: "resumed"))
    }

    @Test("rollout-only resumed work retains its indexed name without expanding unrelated history")
    func rolloutOnlyActiveIdentityOutsideHistoryLimit() throws {
        let fixture = try IndexFixture(lines: [
            line("unrelated-old", title: "Unrelated old history", timestamp: 10),
            line("rollout-parent", title: "Resumed without hooks", timestamp: 20),
            line("history-a", title: "Newer history A", timestamp: 30),
            line("history-b", title: "Newer history B", timestamp: 40),
        ])
        defer { fixture.remove() }

        let tasks = fixture.read(events: [], activeCodexThreadIDs: ["rollout-parent"], now: now,
                                 configuration: .init(recentThreadLimit: 2))

        #expect(Set(tasks.map(\.sourceID)) == ["rollout-parent", "history-a", "history-b"])
        #expect(tasks.first { $0.sourceID == "rollout-parent" }?.title == "Resumed without hooks")
        #expect(tasks.first { $0.sourceID == "rollout-parent" }?.deepLinkURL
            == CodexThreadDeepLink.url(forThreadID: "rollout-parent"))
        #expect(tasks.filter { $0.sourceID.hasPrefix("history-") }.count == 2)
    }

    @Test("completed children and another provider cannot expand Codex history")
    func inactiveAndOtherProviderIdentitiesDoNotExpandHistory() throws {
        let fixture = try IndexFixture(lines: [
            line("old-parent", title: "Older parent", timestamp: 10),
            line("claude-parent", title: "Unrelated Codex identity", timestamp: 20),
            line("history", title: "Recent history", timestamp: 30),
        ])
        defer { fixture.remove() }
        let events = [
            event("child", parent: "old-parent", offset: -2),
            event("child", parent: "old-parent", kind: "stopped", offset: -1),
            event("claude-child", parent: "claude-parent", provider: .claude),
        ]

        let tasks = fixture.read(events: events, now: now, configuration: .init(recentThreadLimit: 1))

        #expect(tasks.filter { $0.provider == .codex }.map(\.sourceID) == ["history"])
        #expect(tasks.contains { $0.provider == .claude && $0.sourceID == "claude-child" })
    }

    @Test("active lookup never reads a parent name beyond the configured index tail")
    func identityLookupRespectsTailBudget() throws {
        let history = line("history", title: "Recent history", timestamp: 30)
        let fixture = try IndexFixture(lines: [
            line("outside-tail", title: "Must not be read", timestamp: 10),
            String(repeating: "x", count: 2_048),
            history,
        ])
        defer { fixture.remove() }
        // Includes the newline before the final complete record, which the
        // bounded reader discards when trimming a partial leading line.
        let byteLimit = history.utf8.count + 2
        let tasks = fixture.read(events: [event("child", parent: "outside-tail")], now: now,
                                 configuration: .init(recentThreadLimit: 1, sessionIndexTailByteLimit: byteLimit))

        #expect(Set(tasks.map(\.sourceID)) == ["child", "history"])
        #expect(!tasks.contains { $0.title == "Must not be read" })
        #expect(tasks.first { $0.sourceID == "child" }?.navigationSourceID == "outside-tail")
    }

    @Test("a zero history limit still resolves active named work only")
    func zeroHistoryRetainsActiveIdentity() throws {
        let fixture = try IndexFixture(lines: [
            line("active", title: "Active named task", timestamp: 10),
            line("history", title: "Unrelated newer history", timestamp: 20),
        ])
        defer { fixture.remove() }

        let tasks = fixture.read(events: [event("active")], now: now,
                                 configuration: .init(recentThreadLimit: 0))

        #expect(tasks.map(\.sourceID) == ["active"])
        #expect(tasks.first?.title == "Active named task")
    }

    private func event(
        _ sourceID: String, parent: String? = nil, provider: PetProvider = .codex,
        kind: String = "tool_started", offset: TimeInterval = -1
    ) -> CodexPetEvent {
        CodexPetEvent(kind: kind, timestamp: now.timeIntervalSince1970 + offset, provider: provider,
                      workspace: "/example/example-project", sessionID: sourceID, parentSessionID: parent)
    }

    private func line(_ id: String, title: String, timestamp: TimeInterval) -> String {
        let date = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: timestamp))
        return #"{"id":"\#(id)","thread_name":"\#(title)","updated_at":"\#(date)"}"#
    }
}

private struct IndexFixture {
    let root: URL
    let index: URL
    let sessions: URL

    init(lines: [String]) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ActiveIdentityTests-\(UUID().uuidString)")
        index = root.appendingPathComponent("session_index.jsonl")
        sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: index, atomically: true, encoding: .utf8)
    }

    func read(
        events: [CodexPetEvent], activeCodexThreadIDs: Set<String> = [], now: Date,
        configuration: PetTaskSummaryConfiguration
    ) -> [PetTaskSummary] {
        CodexTaskSummaryReader.read(sessionIndexURL: index, sessionsRootURL: sessions,
                                   providerEvents: events, activeCodexThreadIDs: activeCodexThreadIDs,
                                   now: now, configuration: configuration)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

import Foundation
import Testing
@testable import CodexPetBarCore

@Suite("Shared playfield participants")
struct PetSharedCompanionsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("working pets remain standing when their tasks finish")
    func completionRetainsParticipants() {
        let prior = [task("first"), task("second")]
        let finished = [task("first", status: .completed), task("second", status: .recent)]
        let result = PetSharedCompanions.strip(tasks: finished, previousTasks: prior, now: now)

        #expect(result.visibleTasks.map(\.sourceID) == ["first", "second"])
        #expect(result.visibleTasks.map(\.status) == [.completed, .recent])
        #expect(result.overflowCount == 0)
        #expect(result.attentionOverflowCount == 0)
    }

    @Test("a missing current record never keeps a previous pet working or falsely completes it")
    func missingRecordsBecomeStandingRecent() throws {
        let prior = task("missing", status: .waiting)
        let retained = try #require(PetSharedCompanions.strip(
            tasks: [], previousTasks: [prior], now: now).visibleTasks.first)

        #expect(retained.status == .recent)
        #expect(retained.id == prior.id)
        #expect(retained.title == prior.title)
        #expect(retained.updatedAt == prior.updatedAt)
        #expect(retained.deepLinkURL == prior.deepLinkURL)
    }

    @Test("attention and running work displace idle pets before overflowing")
    func activeWorkOwnsCapacity() {
        let prior = [task("quiet-a", status: .completed), task("running-a"),
                     task("quiet-b", status: .recent), task("running-b")]
        let current = prior + [task("waiting", status: .waiting), task("new-running")]
        let result = PetSharedCompanions.strip(tasks: current, previousTasks: prior, now: now)

        #expect(result.visibleTasks.map(\.sourceID) == ["running-a", "running-b", "waiting", "new-running"])
        #expect(result.overflowCount == 0)
    }

    @Test("attention can evict running work while surviving pets keep their order")
    func attentionEvictsLowerPriorityWithoutResortingSurvivors() {
        let prior = [task("a"), task("b"), task("c"), task("d")]
        let current = prior + [task("waiting", status: .waiting), task("failed", status: .failed)]
        let result = PetSharedCompanions.strip(tasks: current, previousTasks: prior, now: now)

        #expect(result.visibleTasks.prefix(2).map(\.sourceID) == ["a", "b"])
        #expect(Set(result.visibleTasks.suffix(2).map(\.sourceID)) == ["waiting", "failed"])
        #expect(result.overflowCount == 2)
        #expect(result.attentionOverflowCount == 0)
    }

    @Test("status changes do not reorder surviving participants")
    func survivingOrderIsStable() {
        let prior = [task("z"), task("a"), task("m")]
        let current = [task("m", status: .waiting), task("a", status: .completed), task("z")]
        let result = PetSharedCompanions.strip(tasks: current, previousTasks: prior, now: now)

        #expect(result.visibleTasks.map(\.sourceID) == ["z", "a", "m"])
        #expect(result.visibleTasks.map(\.status) == [.running, .completed, .waiting])
    }

    @Test("a quiet first entry includes at most three tasks from the last day")
    func initialQuietSelectionIsRecentAndSmall() {
        let current = [
            task("old", status: .completed, secondsAgo: 86_401),
            task("future", status: .completed, secondsAgo: -60),
            task("a", status: .completed, secondsAgo: 10),
            task("b", status: .recent, secondsAgo: 20),
            task("c", status: .completed, secondsAgo: 30),
            task("d", status: .recent, secondsAgo: 40),
        ]
        let result = PetSharedCompanions.strip(tasks: current, now: now)

        #expect(result.visibleTasks.map(\.sourceID) == ["a", "b", "c"])
        #expect(result.overflowCount == 0)
        #expect(PetSharedCompanions.strip(tasks: [current[0]], now: now).visibleTasks.isEmpty)
    }

    @Test("initial active work is not padded with unrelated historical pets")
    func workingInitializationDoesNotPadHistory() {
        let result = PetSharedCompanions.strip(tasks: [task("active"),
            task("history-a", status: .completed), task("history-b", status: .recent)], now: now)

        #expect(result.visibleTasks.map(\.sourceID) == ["active"])
    }

    @Test("previously selected idle companions can stay beyond the initial history window")
    func retainedQuietParticipantsDoNotExpire() {
        let selected = task("selected", status: .completed, secondsAgo: 2 * 86_400)
        let result = PetSharedCompanions.strip(tasks: [], previousTasks: [selected], now: now)

        #expect(result.visibleTasks == [selected])
    }

    @Test("overflow counts only hidden active work and hidden attention")
    func overflowExcludesQuietHistory() {
        let attention = (0..<5).map { task("waiting-\($0)", status: .waiting) }
        let current = attention + [task("running")] + (0..<20).map { task("old-\($0)", status: .completed) }
        let result = PetSharedCompanions.strip(tasks: current, now: now)

        #expect(result.visibleTasks.count == 4)
        #expect(result.visibleTasks.allSatisfy { $0.status == .waiting })
        #expect(result.overflowCount == 2)
        #expect(result.attentionOverflowCount == 1)
    }

    @Test("newer completion beats a duplicate running record")
    func currentDuplicatesResolveBeforeSelection() {
        let prior = task("session", secondsAgo: 30)
        let completed = task("session", status: .completed, secondsAgo: 10)
        let result = PetSharedCompanions.strip(tasks: [prior, completed], previousTasks: [prior], now: now)

        #expect(result.visibleTasks == [completed])
        #expect(result.overflowCount == 0)
    }

    @Test("participant limits are bounded and input order does not change initial selection")
    func capacityAndOrderingAreDeterministic() {
        let current = (0..<8).map { task("session-\($0)", secondsAgo: Double($0)) }
        let normal = PetSharedCompanions.strip(tasks: current, now: now)

        #expect(PetSharedCompanions.strip(tasks: current.reversed(), now: now) == normal)
        #expect(PetSharedCompanions.strip(tasks: current, now: now, limit: 99).visibleTasks.count == 4)
        #expect(PetSharedCompanions.strip(tasks: current, now: now, limit: 2).visibleTasks.count == 2)
        let none = PetSharedCompanions.strip(tasks: current, now: now, limit: -1)
        #expect(none.visibleTasks.isEmpty)
        #expect(none.overflowCount == 8)
    }

    @Test("provider namespaces remain distinct when session IDs match")
    func sameSourceIDDoesNotMergeProviders() {
        let current = [task("session"), task("session", provider: .claude)]
        let result = PetSharedCompanions.strip(tasks: current, previousTasks: current, now: now)

        #expect(result.visibleTasks.map(\.id) == ["codex:session", "claude:session"])
    }

    private func task(_ id: String, status: PetTaskStatus = .running,
                      secondsAgo: TimeInterval = 10, provider: PetProvider = .codex) -> PetTaskSummary {
        PetTaskSummary(sourceID: id, navigationSourceID: id, provider: provider,
            title: "Task \(id)", detail: "Task detail", status: status,
            project: .derived(fromWorkspace: "/example/project"), updatedAt: now.addingTimeInterval(-secondsAgo),
            deepLinkURL: provider == .codex ? CodexThreadDeepLink.url(forThreadID: id) : nil)
    }
}

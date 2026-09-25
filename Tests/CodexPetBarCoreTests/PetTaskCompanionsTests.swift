import Foundation
import Testing
@testable import CodexPetBarCore

@Suite("Task companions")
struct PetTaskCompanionsTests {
    @Test("initial choices are independent of task and library order")
    func deterministicAssignments() {
        let tasks = [task("alpha"), task("beta"), task("gamma")]
        let pets = [pet("goblin"), pet("robot"), pet("cat")]
        let assignments = PetTaskCompanions.assignments(tasks: tasks, pets: pets)

        #expect(assignments == PetTaskCompanions.assignments(tasks: tasks.reversed(), pets: pets.reversed()))
        #expect(assignments == ["codex:alpha": "cat", "codex:beta": "goblin", "codex:gamma": "robot"])
        #expect(Set(assignments.values).count == 3)
        #expect(assignments.count == 3)
    }

    @Test("remembered choices survive refresh, disappearance, and reappearance")
    func choicesSurviveFeedChanges() {
        let pets = [pet("goblin"), pet("robot"), pet("cat")]
        let first = PetTaskCompanions.assignments(tasks: [task("alpha"), task("beta")], pets: pets)
        let next = PetTaskCompanions.assignments(tasks: [task("beta"), task("gamma")], pets: pets, previous: first)
        let restored = PetTaskCompanions.assignments(
            tasks: [task("gamma"), task("beta"), task("alpha")], pets: pets.reversed(), previous: next
        )

        #expect(next["codex:alpha"] == first["codex:alpha"])
        #expect(next["codex:beta"] == first["codex:beta"])
        #expect(restored == next)
        #expect(PetTaskCompanions.assignments(tasks: [], pets: pets, previous: restored) == restored)
    }

    @Test("new tasks use free companions before sharing")
    func newTasksPreferUnusedPets() {
        let tasks = [task("alpha"), task("beta"), task("gamma"), task("delta")]
        let pets = [pet("goblin"), pet("robot"), pet("cat")]
        let initial = ["codex:alpha": "robot", "codex:missing": "goblin"]
        let choices = PetTaskCompanions.assignments(tasks: Array(tasks.prefix(3)), pets: pets, previous: initial)
        let overflowing = PetTaskCompanions.assignments(tasks: tasks, pets: pets, previous: choices)

        #expect(choices["codex:alpha"] == "robot")
        #expect(Set(tasks.prefix(3).compactMap { choices[$0.id] }).count == 3)
        #expect(overflowing["codex:delta"] != nil)
        #expect(Set(tasks.compactMap { overflowing[$0.id] }).count == 3)
        #expect(choices["codex:missing"] == "goblin")
    }

    @Test("valid overrides win and invalid overrides cannot erase an existing pet")
    func validateOverrides() {
        let tasks = [task("alpha"), task("beta"), task("gamma")]
        let choices = PetTaskCompanions.assignments(
            tasks: tasks,
            pets: [pet("cat"), pet("goblin"), pet("robot")],
            previous: ["codex:alpha": "cat", "codex:beta": "goblin"],
            overrides: ["codex:alpha": "robot", "codex:beta": "removed", "codex:gamma": "robot"]
        )

        #expect(choices["codex:alpha"] == "robot")
        #expect(choices["codex:beta"] == "goblin")
        #expect(choices["codex:gamma"] == "robot")
    }

    @Test("removed pets are replaced without changing surviving choices")
    func missingPetsFallBack() {
        let tasks = [task("alpha"), task("beta")]
        let choices = PetTaskCompanions.assignments(
            tasks: tasks, pets: [pet("cat"), pet("robot")],
            previous: ["codex:alpha": "removed", "codex:beta": "robot", "codex:gone": "removed"]
        )

        #expect(choices == ["codex:alpha": "cat", "codex:beta": "robot"])
        #expect(PetTaskCompanions.assignments(tasks: tasks, pets: [], previous: choices).isEmpty)
        #expect(PetTaskCompanions.assignments(tasks: tasks, pets: [pet("")], previous: choices).isEmpty)
    }

    @Test("matching source IDs from different providers have independent choices")
    func providerNamespacing() {
        let tasks = [task("same", provider: .codex), task("same", provider: .claude), task("same", provider: .cursor)]
        let choices = PetTaskCompanions.assignments(tasks: tasks, pets: [pet("cat"), pet("goblin"), pet("robot")])

        #expect(Set(choices.keys) == Set(tasks.map(\.id)))
        #expect(Set(choices.values).count == 3)
    }

    @Test("attention leads work and refreshed timestamps do not shuffle companions")
    func stripPriorityAndStablePositions() {
        let tasks = [
            task("working-b", timestamp: 400),
            task("waiting-b", status: .waiting, timestamp: 100),
            task("working-a", timestamp: 300),
            task("waiting-a", status: .failed, timestamp: 200),
            task("finished", status: .completed, timestamp: 900),
        ]
        let strip = PetTaskCompanions.strip(tasks: tasks)
        let refreshed = tasks.reversed().map {
            task($0.sourceID, status: $0.status, timestamp: 1_000 - $0.updatedAt.timeIntervalSince1970)
        }

        #expect(strip.visibleTasks.map(\.sourceID) == ["waiting-a", "waiting-b", "working-a", "working-b"])
        #expect(PetTaskCompanions.strip(tasks: refreshed).visibleTasks.map(\.id) == strip.visibleTasks.map(\.id))
        #expect(strip.overflowCount == 0)
    }

    @Test("only hidden active tasks count toward overflow and attention overflow")
    func stripOverflow() {
        let tasks = (0..<5).map { task("waiting-\($0)", status: .waiting) }
            + [task("working"), task("finished", status: .completed), task("history", status: .recent)]
        let strip = PetTaskCompanions.strip(tasks: tasks, limit: 50)

        #expect(strip.visibleTasks.count == 4)
        #expect(strip.overflowCount == 2)
        #expect(strip.attentionOverflowCount == 1)
        #expect(PetTaskCompanions.strip(tasks: tasks, limit: 2).overflowCount == 4)
        #expect(PetTaskCompanions.strip(tasks: tasks, limit: -1).visibleTasks.isEmpty)
        #expect(PetTaskCompanions.strip(tasks: tasks, limit: 0).attentionOverflowCount == 5)
    }

    @Test("all-quiet tasks leave the menu strip empty for the single companion fallback")
    func stripAllQuiet() {
        let strip = PetTaskCompanions.strip(tasks: [task("done", status: .completed), task("history", status: .recent)])

        #expect(strip.visibleTasks.isEmpty)
        #expect(strip.overflowCount == 0)
        #expect(strip.attentionOverflowCount == 0)
        #expect(PetTaskCompanions.strip(tasks: []).visibleTasks.isEmpty)
    }

    @Test("duplicate source summaries use the latest state exactly once")
    func stripDeduplicatesSummaries() {
        let tasks = [
            task("changed", status: .waiting, timestamp: 100),
            task("changed", status: .completed, timestamp: 200),
            task("still-working", timestamp: 150),
            task("still-working", timestamp: 100),
        ]

        #expect(PetTaskCompanions.strip(tasks: tasks).visibleTasks.map(\.sourceID) == ["still-working"])
        #expect(PetTaskCompanions.strip(tasks: tasks.reversed()) == PetTaskCompanions.strip(tasks: tasks))
    }

    private func task(
        _ id: String, provider: PetProvider = .codex, status: PetTaskStatus = .running,
        timestamp: TimeInterval = 100
    ) -> PetTaskSummary {
        PetTaskSummary(sourceID: id, provider: provider, title: id, detail: "Task detail", status: status,
                       project: .other, updatedAt: Date(timeIntervalSince1970: timestamp))
    }

    private func pet(_ id: String) -> PetPackage {
        let directory = URL(fileURLWithPath: "/example/pets/\(id)")
        return PetPackage(id: id, displayName: id, description: "Test companion", directoryURL: directory,
                          spritesheetURL: directory.appendingPathComponent("spritesheet.png"))
    }
}

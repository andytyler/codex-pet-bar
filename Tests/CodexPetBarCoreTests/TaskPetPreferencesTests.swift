import Foundation
import Testing
@testable import CodexPetBarCore

@Suite("Task pet preferences")
struct TaskPetPreferencesTests {
    @Test("Existing installs keep one companion until they choose task pets")
    func defaultsAndPersistence() throws {
        let name = "dev.ajt.PetBarTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppPreferences(defaults: defaults)
        #expect(preferences.displayMode == .companion)
        #expect(preferences.taskPetAssignments.isEmpty)
        preferences.displayMode = .taskPets
        preferences.taskPetAssignments = ["codex:one": "boo", "claude:one": "grumble"]
        let reloaded = AppPreferences(defaults: try #require(UserDefaults(suiteName: name)))
        #expect(reloaded.displayMode == .taskPets)
        #expect(reloaded.taskPetAssignments == ["codex:one": "boo", "claude:one": "grumble"])
        defaults.set("unknown-mode", forKey: "displayMode")
        #expect(preferences.displayMode == .companion)
    }
}

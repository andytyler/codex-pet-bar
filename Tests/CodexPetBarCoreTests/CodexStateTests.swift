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
        #expect(CodexActivity.idle.animationState == .waiting)
        #expect(CodexActivity.running.animationState == .running)
        #expect(CodexActivity.reviewing.animationState == .review)
        #expect(CodexActivity.listening.animationState == .review)
        #expect(CodexActivity.failed.animationState == .failed)
    }
}

private func isolatedDefaults() throws -> UserDefaults {
    let suiteName = "CodexPetBarTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
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

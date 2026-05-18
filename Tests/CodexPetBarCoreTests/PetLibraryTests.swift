import Foundation
import Testing
@testable import CodexPetBarCore

@Suite("PetLibrary")
struct PetLibraryTests {
    @Test("loads only valid pets and sorts by display name")
    func loadsOnlyValidPetsSortedByDisplayName() throws {
        let root = try TemporaryDirectory()
        try root.createPet(
            id: "zeta",
            displayName: "Zeta",
            description: "A valid pet.",
            spritesheetName: "spritesheet.webp"
        )
        try root.createPet(
            id: "alpha",
            displayName: "Alpha",
            description: "A valid pet.",
            spritesheetName: "sprite.webp"
        )
        try root.createInvalidJSONPet(id: "broken")
        try root.createMissingSpritesheetPet(id: "missing")

        let pets = PetLibrary(petsDirectory: root.url).loadPets()

        #expect(pets.map(\.id) == ["alpha", "zeta"])
        #expect(pets.map(\.displayName) == ["Alpha", "Zeta"])
        #expect(pets.first?.spritesheetURL.lastPathComponent == "sprite.webp")
    }
}

private struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPetBarTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func createPet(id: String, displayName: String, description: String, spritesheetName: String) throws {
        let directory = url.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest = """
        {
          "id": "\(id)",
          "displayName": "\(displayName)",
          "description": "\(description)",
          "spritesheetPath": "\(spritesheetName)"
        }
        """
        try manifest.write(
            to: directory.appendingPathComponent("pet.json"),
            atomically: true,
            encoding: .utf8
        )
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: directory.appendingPathComponent(spritesheetName))
    }

    func createInvalidJSONPet(id: String) throws {
        let directory = url.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "{".write(
            to: directory.appendingPathComponent("pet.json"),
            atomically: true,
            encoding: .utf8
        )
        try Data([0]).write(to: directory.appendingPathComponent("spritesheet.webp"))
    }

    func createMissingSpritesheetPet(id: String) throws {
        let directory = url.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest = """
        {
          "id": "\(id)",
          "displayName": "Missing",
          "description": "No spritesheet.",
          "spritesheetPath": "spritesheet.webp"
        }
        """
        try manifest.write(
            to: directory.appendingPathComponent("pet.json"),
            atomically: true,
            encoding: .utf8
        )
    }
}

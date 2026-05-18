import Foundation

public struct PetLibrary {
    public let petsDirectory: URL
    private let fileManager: FileManager

    public init(petsDirectory: URL, fileManager: FileManager = .default) {
        self.petsDirectory = petsDirectory
        self.fileManager = fileManager
    }

    public static func defaultPetsDirectory(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("pets", isDirectory: true)
    }

    public func loadPets() -> [PetPackage] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: petsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries
            .compactMap(loadPetPackage(at:))
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    private func loadPetPackage(at directory: URL) -> PetPackage? {
        guard isDirectory(directory) else {
            return nil
        }

        let manifestURL = directory.appendingPathComponent("pet.json")
        guard
            let data = try? Data(contentsOf: manifestURL),
            let manifest = try? JSONDecoder().decode(PetManifest.self, from: data)
        else {
            return nil
        }

        let spritesheetURL = directory.appendingPathComponent(manifest.spritesheetPath)
        guard fileManager.fileExists(atPath: spritesheetURL.path) else {
            return nil
        }

        return PetPackage(
            id: manifest.id,
            displayName: manifest.displayName,
            description: manifest.description,
            directoryURL: directory,
            spritesheetURL: spritesheetURL
        )
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

private struct PetManifest: Decodable {
    let id: String
    let displayName: String
    let description: String
    let spritesheetPath: String
}

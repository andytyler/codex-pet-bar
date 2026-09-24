import Foundation

public struct PetLoadIssue: Equatable, Sendable {
    public let packageName: String
    public let message: String

    public init(packageName: String, message: String) {
        self.packageName = packageName
        self.message = message
    }
}

public struct PetLibraryLoadResult: Equatable, Sendable {
    public let pets: [PetPackage]
    public let issues: [PetLoadIssue]

    public init(pets: [PetPackage], issues: [PetLoadIssue]) {
        self.pets = pets
        self.issues = issues
    }
}

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
        loadPetsWithDiagnostics().pets
    }

    public func loadPetsWithDiagnostics() -> PetLibraryLoadResult {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: petsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return PetLibraryLoadResult(pets: [], issues: [])
        }

        let candidates = entries.compactMap(loadPetPackage(at:))
        let pets = candidates.compactMap { $0.pet }.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        let issues = candidates.compactMap { $0.issue }.sorted {
            $0.packageName.localizedCaseInsensitiveCompare($1.packageName) == .orderedAscending
        }
        return PetLibraryLoadResult(pets: pets, issues: issues)
    }

    private func loadPetPackage(at directory: URL) -> (pet: PetPackage?, issue: PetLoadIssue?)? {
        guard isDirectory(directory) else {
            return nil
        }

        let packageName = directory.lastPathComponent
        let manifestURL = directory.appendingPathComponent("pet.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            return (nil, PetLoadIssue(packageName: packageName, message: "missing pet.json"))
        }
        guard let manifest = try? JSONDecoder().decode(PetManifest.self, from: data) else {
            return (nil, PetLoadIssue(packageName: packageName, message: "invalid pet.json"))
        }

        let spritesheetPath = manifest.spritesheetPath as NSString
        guard !spritesheetPath.isAbsolutePath, !spritesheetPath.pathComponents.contains("..") else {
            return (nil, PetLoadIssue(packageName: manifest.id, message: "spritesheetPath must stay inside the pet folder"))
        }

        let spritesheetURL = directory.appendingPathComponent(manifest.spritesheetPath)
        guard fileManager.fileExists(atPath: spritesheetURL.path) else {
            return (nil, PetLoadIssue(packageName: manifest.id, message: "missing \(manifest.spritesheetPath)"))
        }

        return (
            PetPackage(
                id: manifest.id,
                displayName: manifest.displayName,
                description: manifest.description,
                directoryURL: directory,
                spritesheetURL: spritesheetURL,
                spriteVersionNumber: manifest.spriteVersionNumber
            ),
            nil
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
    let spriteVersionNumber: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case description
        case spritesheetPath
        case spriteVersionNumber
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        description = try container.decode(String.self, forKey: .description)
        spritesheetPath = try container.decode(String.self, forKey: .spritesheetPath)

        if container.contains(.spriteVersionNumber) {
            spriteVersionNumber = try container.decode(Int.self, forKey: .spriteVersionNumber)
        } else {
            spriteVersionNumber = 1
        }

        guard PetAtlasMetadata.rowCount(forSpriteVersionNumber: spriteVersionNumber) != nil else {
            throw DecodingError.dataCorruptedError(
                forKey: .spriteVersionNumber,
                in: container,
                debugDescription: "spriteVersionNumber must be 1 or 2"
            )
        }
    }
}

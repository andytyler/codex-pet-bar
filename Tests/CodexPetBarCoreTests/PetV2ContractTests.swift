import Foundation
import Testing
@testable import CodexPetBarCore

@Suite("Pet v2 contract")
struct PetV2ContractTests {
    @Test("PetPackage initializer remains source compatible and defaults to v1")
    func petPackageDefaultsToV1() {
        let package = PetPackage(
            id: "classic",
            displayName: "Classic",
            description: "A v1 pet.",
            directoryURL: URL(fileURLWithPath: "/tmp/classic"),
            spritesheetURL: URL(fileURLWithPath: "/tmp/classic/spritesheet.webp")
        )

        #expect(package.spriteVersionNumber == 1)
    }

    @Test("manifest versions default to v1 and preserve explicit supported versions")
    func manifestVersionDecoding() throws {
        let root = try TemporaryPetV2Directory()
        try root.createPet(id: "omitted", spriteVersionJSON: nil)
        try root.createPet(id: "one", spriteVersionJSON: "1")
        try root.createPet(id: "two", spriteVersionJSON: "2")

        let petsByID = Dictionary(
            uniqueKeysWithValues: PetLibrary(petsDirectory: root.url)
                .loadPets()
                .map { ($0.id, $0) }
        )

        #expect(petsByID.count == 3)
        #expect(petsByID["omitted"]?.spriteVersionNumber == 1)
        #expect(petsByID["one"]?.spriteVersionNumber == 1)
        #expect(petsByID["two"]?.spriteVersionNumber == 2)
    }

    @Test("manifests reject unsupported and malformed explicit versions")
    func manifestRejectsUnsupportedVersions() throws {
        let root = try TemporaryPetV2Directory()
        try root.createPet(id: "zero", spriteVersionJSON: "0")
        try root.createPet(id: "three", spriteVersionJSON: "3")
        try root.createPet(id: "negative", spriteVersionJSON: "-1")
        try root.createPet(id: "string", spriteVersionJSON: #""2""#)
        try root.createPet(id: "null", spriteVersionJSON: "null")

        #expect(PetLibrary(petsDirectory: root.url).loadPets().isEmpty)
    }

    @Test("atlas row count follows the sprite contract version")
    func atlasRowsFollowSpriteVersion() {
        #expect(PetAtlasMetadata.v1Rows == 9)
        #expect(PetAtlasMetadata.v2Rows == 11)
        #expect(PetAtlasMetadata.rows == 9)
        #expect(PetAtlasMetadata.rowCount(forSpriteVersionNumber: 1) == 9)
        #expect(PetAtlasMetadata.rowCount(forSpriteVersionNumber: 2) == 11)
        #expect(PetAtlasMetadata.rowCount(forSpriteVersionNumber: 0) == nil)
        #expect(PetAtlasMetadata.rowCount(forSpriteVersionNumber: 3) == nil)
    }

    @Test("cardinal vectors map clockwise from up across the two directional rows")
    func cardinalDirectionMapping() {
        #expect(frame(x: 0, y: 1) == .init(rowIndex: 9, columnIndex: 0, headingIndex: 0))
        #expect(frame(x: 1, y: 0) == .init(rowIndex: 9, columnIndex: 4, headingIndex: 4))
        #expect(frame(x: 0, y: -1) == .init(rowIndex: 10, columnIndex: 0, headingIndex: 8))
        #expect(frame(x: -1, y: 0) == .init(rowIndex: 10, columnIndex: 4, headingIndex: 12))
    }

    @Test("all 16 heading centers fill rows 9 and 10 in order")
    func everyDirectionalHeadingCenter() {
        for headingIndex in 0..<16 {
            let vector = vector(clockwiseDegreesFromUp: Double(headingIndex) * 22.5)
            let expected = PetAtlasMetadata.DirectionalFrame(
                rowIndex: 9 + headingIndex / 8,
                columnIndex: headingIndex % 8,
                headingIndex: headingIndex
            )

            #expect(frame(x: vector.x, y: vector.y) == expected)
        }
    }

    @Test("sector boundaries choose the clockwise frame")
    func directionalSectorBoundaries() {
        let belowFirstBoundary = vector(clockwiseDegreesFromUp: 11.25 - 0.000_001)
        let firstBoundary = vector(clockwiseDegreesFromUp: 11.25)
        let aboveFirstBoundary = vector(clockwiseDegreesFromUp: 11.25 + 0.000_001)
        let belowWrapBoundary = vector(clockwiseDegreesFromUp: 348.75 - 0.000_001)
        let wrapBoundary = vector(clockwiseDegreesFromUp: 348.75)
        let aboveWrapBoundary = vector(clockwiseDegreesFromUp: 348.75 + 0.000_001)

        #expect(frame(x: belowFirstBoundary.x, y: belowFirstBoundary.y)?.headingIndex == 0)
        #expect(frame(x: firstBoundary.x, y: firstBoundary.y)?.headingIndex == 1)
        #expect(frame(x: aboveFirstBoundary.x, y: aboveFirstBoundary.y)?.headingIndex == 1)
        #expect(frame(x: belowWrapBoundary.x, y: belowWrapBoundary.y)?.headingIndex == 15)
        #expect(frame(x: wrapBoundary.x, y: wrapBoundary.y)?.headingIndex == 0)
        #expect(frame(x: aboveWrapBoundary.x, y: aboveWrapBoundary.y)?.headingIndex == 0)
    }

    @Test("deadzone suppresses tiny vectors and can be configured")
    func directionalDeadzone() {
        #expect(PetAtlasMetadata.directionalFrame(x: 0, y: 0) == nil)
        #expect(PetAtlasMetadata.directionalFrame(x: 0.006, y: 0.008, deadzone: 0.01) == nil)
        #expect(PetAtlasMetadata.directionalFrame(x: 0.006, y: 0.008, deadzone: 0.009) != nil)
        #expect(PetAtlasMetadata.directionalFrame(x: 0, y: 0.02) != nil)
        #expect(PetAtlasMetadata.directionalFrame(x: .nan, y: 1) == nil)
        #expect(PetAtlasMetadata.directionalFrame(x: 0, y: 1, deadzone: -1) == nil)
    }

    private func frame(x: Double, y: Double) -> PetAtlasMetadata.DirectionalFrame? {
        PetAtlasMetadata.directionalFrame(x: x, y: y, deadzone: 0)
    }

    private func vector(clockwiseDegreesFromUp degrees: Double) -> (x: Double, y: Double) {
        let radians = degrees * Double.pi / 180
        return (sin(radians), cos(radians))
    }
}

private struct TemporaryPetV2Directory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPetV2Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func createPet(id: String, spriteVersionJSON: String?) throws {
        let directory = url.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let versionField = spriteVersionJSON.map { ",\n  \"spriteVersionNumber\": \($0)" } ?? ""
        let manifest = """
        {
          "id": "\(id)",
          "displayName": "\(id)",
          "description": "Version fixture.",
          "spritesheetPath": "spritesheet.webp"\(versionField)
        }
        """

        try manifest.write(
            to: directory.appendingPathComponent("pet.json"),
            atomically: true,
            encoding: .utf8
        )
        try Data([0x52, 0x49, 0x46, 0x46]).write(
            to: directory.appendingPathComponent("spritesheet.webp")
        )
    }
}

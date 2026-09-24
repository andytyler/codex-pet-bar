import Testing
@testable import CodexPetBarCore

@Suite("Animation atlas")
struct AnimationAtlasTests {
    @Test("Codex atlas uses 8 columns and 9 rows of 192 by 208 cells")
    func atlasGeometryMatchesCodexPetContract() {
        #expect(PetAtlasMetadata.columns == 8)
        #expect(PetAtlasMetadata.rows == 9)
        #expect(PetAtlasMetadata.cellWidth == 192)
        #expect(PetAtlasMetadata.cellHeight == 208)
    }

    @Test("animation rows match Codex pet row order and frame timings")
    func animationRowsMatchReference() throws {
        let rows = PetAtlasMetadata.rowsByState

        #expect(rows[.idle]?.rowIndex == 0)
        #expect(rows[.idle]?.frameDurationsMS == [280, 110, 110, 140, 140, 320])
        #expect(rows[.runningRight]?.rowIndex == 1)
        #expect(rows[.runningRight]?.usedColumns == Array(0...7))
        #expect(rows[.runningLeft]?.rowIndex == 2)
        #expect(rows[.waving]?.rowIndex == 3)
        #expect(rows[.jumping]?.rowIndex == 4)
        #expect(rows[.failed]?.rowIndex == 5)
        #expect(rows[.waiting]?.rowIndex == 6)
        #expect(rows[.running]?.rowIndex == 7)
        #expect(rows[.review]?.rowIndex == 8)
    }

    @Test("idle playback uses the current six-times-slower cadence")
    func idlePlaybackUsesSlowCadence() throws {
        let baseIdle = try #require(PetAtlasMetadata.rowsByState[.idle])
        let playbackIdle = try #require(PetAtlasMetadata.playbackRow(for: .idle))

        #expect(playbackIdle.frameDurationsMS == baseIdle.frameDurationsMS.map { $0 * 6 })
        #expect(PetAtlasMetadata.playbackRow(for: .running) == PetAtlasMetadata.rowsByState[.running])
    }
}

import Testing
@testable import CodexPetBarCore

@Suite("Pet frame alpha bounds")
struct PetFrameAlphaBoundsTests {
    @Test("content bounds ignore transparent frame padding")
    func contentBoundsIgnoreTransparentFramePadding() {
        let alpha: [UInt8] = [
            0, 0, 0, 0, 0,
            0, 0, 9, 0, 0,
            0, 7, 8, 6, 0,
            0, 0, 0, 0, 0
        ]

        let bounds = PetFrameAlphaBounds.contentBounds(
            alpha: alpha,
            width: 5,
            height: 4,
            threshold: 1
        )

        #expect(bounds == PetFrameAlphaBounds(x: 1, y: 1, width: 3, height: 2))
    }

    @Test("padded bounds clamp to frame edges")
    func paddedBoundsClampToFrameEdges() {
        let bounds = PetFrameAlphaBounds(x: 1, y: 0, width: 2, height: 2)

        #expect(bounds.padded(by: 2, withinWidth: 5, height: 4) == PetFrameAlphaBounds(x: 0, y: 0, width: 5, height: 4))
    }

    @Test("union preserves visible motion across frames")
    func unionPreservesVisibleMotionAcrossFrames() {
        let bounds = PetFrameAlphaBounds.union([
            PetFrameAlphaBounds(x: 2, y: 3, width: 4, height: 5),
            PetFrameAlphaBounds(x: 1, y: 6, width: 7, height: 2)
        ])

        #expect(bounds == PetFrameAlphaBounds(x: 1, y: 3, width: 7, height: 5))
    }
}

import AppKit
import Testing
@testable import CodexPetBarCore

@Suite("Codex pet assets")
struct CodexPetAssetsTests {
    @Test("bundles the Codex glyph icon for thread badges")
    func bundlesCodexGlyphIconForThreadBadges() throws {
        let image = try #require(NSImage(contentsOf: CodexPetAssets.codexAppIconURL))

        #expect(image.size.width == 256)
        #expect(image.size.height == 256)
    }
}

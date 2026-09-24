import AppKit
import Testing
@testable import CodexPetBarCore

@Suite("Codex pet assets")
struct CodexPetAssetsTests {
    @Test("bundles the Pet Bar app identity icon")
    func bundlesPetBarAppIdentityIcon() throws {
        let image = try #require(NSImage(contentsOf: CodexPetAssets.codexAppIconURL))

        #expect(image.size.width == 256)
        #expect(image.size.height == 256)
    }

    @Test("bundles separate Codex app and adaptive flag artwork")
    func bundlesAdaptiveCodexOutline() throws {
        let appIconData = try Data(contentsOf: CodexPetAssets.codexProviderAppIconURL)
        let appIcon = try #require(NSBitmapImageRep(data: appIconData))
        let data = try Data(contentsOf: CodexPetAssets.codexThreadGlyphURL)
        let bitmap = try #require(NSBitmapImageRep(data: data))

        #expect(appIcon.pixelsWide == 320)
        #expect(appIcon.pixelsHigh == 320)
        #expect(appIcon.hasAlpha)
        #expect(bitmap.pixelsWide == 256)
        #expect(bitmap.pixelsHigh == 256)
        #expect(bitmap.hasAlpha)
        #expect(sampledOpaqueWhitePixelCount(in: bitmap) > 20)
    }

    @Test("bundles official provider marks")
    func bundlesOfficialProviderMarks() throws {
        let claude = try #require(NSImage(contentsOf: CodexPetAssets.claudeCodeCrabURL))
        let cursorLight = try #require(NSImage(contentsOf: CodexPetAssets.cursorProviderIconLightURL))
        let cursorDark = try #require(NSImage(contentsOf: CodexPetAssets.cursorProviderIconDarkURL))

        #expect(claude.size.width > 0)
        #expect(claude.size.height > 0)
        #expect(cursorLight.size.width > 0)
        #expect(cursorLight.size.height > 0)
        #expect(cursorDark.size.width > 0)
        #expect(cursorDark.size.height > 0)
    }
}

private func sampledOpaqueWhitePixelCount(in bitmap: NSBitmapImageRep) -> Int {
    var count = 0

    for y in stride(from: 0, to: bitmap.pixelsHigh, by: 8) {
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 8) {
            guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.5 else {
                continue
            }

            if color.redComponent > 0.85, color.greenComponent > 0.85, color.blueComponent > 0.85 {
                count += 1
            }
        }
    }

    return count
}

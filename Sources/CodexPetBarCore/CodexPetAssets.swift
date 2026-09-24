import Foundation

public enum CodexPetAssets {
    public static let claudeCodeCrabURL = resourceURL(
        named: "ClaudeCodeCrab",
        extension: "svg"
    )

    public static let codexProviderAppIconURL = resourceURL(
        named: "CodexProviderAppIcon",
        extension: "png"
    )

    public static let cursorProviderIconLightURL = resourceURL(
        named: "CursorProviderIconLight",
        extension: "svg"
    )

    public static let cursorProviderIconDarkURL = resourceURL(
        named: "CursorProviderIconDark",
        extension: "svg"
    )

    public static let codexAppIconURL: URL = {
        if let appResourceURL = Bundle.main.url(forResource: "CodexAppIcon", withExtension: "png") {
            return appResourceURL
        }

        return Bundle.module.url(
            forResource: "CodexAppIcon",
            withExtension: "png"
        )!
    }()

    public static let codexThreadGlyphURL: URL = {
        if let appResourceURL = Bundle.main.url(forResource: "CodexThreadGlyph", withExtension: "png") {
            return appResourceURL
        }

        return Bundle.module.url(
            forResource: "CodexThreadGlyph",
            withExtension: "png"
        )!
    }()

    private static func resourceURL(named name: String, extension fileExtension: String) -> URL {
        if let appResourceURL = Bundle.main.url(forResource: name, withExtension: fileExtension) {
            return appResourceURL
        }

        return Bundle.module.url(forResource: name, withExtension: fileExtension)!
    }
}

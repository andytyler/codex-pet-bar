import Foundation

public enum CodexPetAssets {
    public static let codexAppIconURL: URL = {
        if let appResourceURL = Bundle.main.url(forResource: "CodexAppIcon", withExtension: "png") {
            return appResourceURL
        }

        return Bundle.module.url(
            forResource: "CodexAppIcon",
            withExtension: "png"
        )!
    }()
}

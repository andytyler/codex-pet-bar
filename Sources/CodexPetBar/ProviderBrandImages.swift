import AppKit
import CodexPetBarCore

@MainActor
enum ProviderBrandImages {
    private static let claudeCodeCrab = load(CodexPetAssets.claudeCodeCrabURL, template: false)
    private static let cursorLight = load(CodexPetAssets.cursorProviderIconLightURL, template: false)
    private static let cursorDark = load(CodexPetAssets.cursorProviderIconDarkURL, template: false)
    private static let codexAppIcon = load(CodexPetAssets.codexProviderAppIconURL, template: false)
    private static let codexGlyph = load(CodexPetAssets.codexThreadGlyphURL, template: true)
    private static var statusFlagCache: [StatusFlagCacheKey: NSImage] = [:]

    /// Full-colour provider artwork used inside the app's panels and menus.
    static func inAppImage(for provider: PetProvider, isDark: Bool) -> NSImage? {
        return switch provider {
        case .codex:
            codexAppIcon
        case .claude:
            claudeCodeCrab
        case .cursor:
            isDark ? cursorDark : cursorLight
        }
    }

    /// Full-colour provider artwork used inside the app's panels and menus.
    static func inAppImage(for provider: PetTaskProviderPresentation, isDark: Bool) -> NSImage? {
        switch provider {
        case .codex:
            return codexAppIcon
        case .claude:
            return claudeCodeCrab
        case .cursor:
            return isDark ? cursorDark : cursorLight
        case .other:
            let image = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "Agent")
            image?.isTemplate = true
            return image
        }
    }

    static func menuImage(
        for provider: PetTaskProviderPresentation,
        appearance: NSAppearance,
        dimension: CGFloat = 16
    ) -> NSImage? {
        guard let source = inAppImage(for: provider, isDark: isDark(appearance)) else {
            return nil
        }
        return fittedImage(source, dimension: dimension)
    }

    static func menuImage(
        for provider: PetProvider,
        appearance: NSAppearance,
        dimension: CGFloat = 16
    ) -> NSImage? {
        guard let source = inAppImage(for: provider, isDark: isDark(appearance)) else {
            return nil
        }
        return fittedImage(source, dimension: dimension)
    }

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static func statusFlagImage(
        for provider: PetProvider,
        isDark: Bool,
        dimension: CGFloat
    ) -> NSImage? {
        let quantizedDimension = max(2, min(16, Int(dimension.rounded())))
        let key = StatusFlagCacheKey(
            provider: provider,
            isDark: isDark,
            dimension: quantizedDimension
        )
        if let cached = statusFlagCache[key] {
            return cached
        }
        guard let source = statusFlagSource(for: provider, isDark: isDark) else {
            return nil
        }
        let fitted: NSImage
        if provider == .codex {
            fitted = tintedFittedImage(
                source,
                color: isDark ? .white : .black,
                dimension: CGFloat(quantizedDimension)
            )
        } else {
            fitted = fittedImage(source, dimension: CGFloat(quantizedDimension))
        }
        statusFlagCache[key] = fitted
        return fitted
    }

    private static func statusFlagSource(for provider: PetProvider, isDark: Bool) -> NSImage? {
        switch provider {
        case .codex:
            codexGlyph
        case .claude:
            claudeCodeCrab
        case .cursor:
            isDark ? cursorDark : cursorLight
        }
    }

    private static func load(_ url: URL, template: Bool) -> NSImage? {
        let image = NSImage(contentsOf: url)
        image?.isTemplate = template
        return image
    }

    static func fittedImage(_ source: NSImage, dimension: CGFloat) -> NSImage {
        let output = NSImage(size: NSSize(width: dimension, height: dimension))
        let sourceSize = source.size
        let scale = min(dimension / max(1, sourceSize.width), dimension / max(1, sourceSize.height))
        let drawSize = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let drawRect = NSRect(
            x: (dimension - drawSize.width) / 2,
            y: (dimension - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )

        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: drawRect)
        output.unlockFocus()
        output.isTemplate = source.isTemplate
        return output
    }

    private static func tintedFittedImage(
        _ source: NSImage,
        color: NSColor,
        dimension: CGFloat
    ) -> NSImage {
        let fitted = fittedImage(source, dimension: dimension)
        let output = NSImage(size: fitted.size)
        let bounds = NSRect(origin: .zero, size: fitted.size)
        output.lockFocus()
        fitted.draw(in: bounds)
        if let context = NSGraphicsContext.current?.cgContext {
            context.setBlendMode(.sourceIn)
            context.setFillColor(color.cgColor)
            context.fill(bounds)
        }
        output.unlockFocus()
        output.isTemplate = false
        return output
    }

    private struct StatusFlagCacheKey: Hashable {
        let provider: PetProvider
        let isDark: Bool
        let dimension: Int
    }
}

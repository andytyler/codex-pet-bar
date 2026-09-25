import AppKit
import CodexPetBarCore

/// An offscreen render of the production strip, with synthetic navigation only.
/// The strip never joins a window, so its animation timer cannot start.
@MainActor
enum PetTaskStripPreviewRenderer {
    static func render(to url: URL, dark: Bool = false) throws {
        let pets = PetLibrary(petsDirectory: CodexEnvironment.homeDirectory()
            .appendingPathComponent("pets", isDirectory: true)).loadPetsWithDiagnostics().pets
        guard !pets.isEmpty else { throw PreviewError.noPets }

        let tasks = [
            task("approve-release", title: "Approve the release", provider: .codex, state: .waiting),
            task("review-settings", title: "Review the new settings", provider: .claude, state: .waiting),
            task("keyboard-check", title: "Fix the failing keyboard check", provider: .cursor, state: .failed),
            task("task-sidebar", title: "Build the task sidebar", provider: .codex, state: .running),
        ]
        let companions = Dictionary(uniqueKeysWithValues: tasks.enumerated().map {
            ($0.element.id, pets[$0.offset % pets.count])
        })
        // Decode failures must fail the preview rather than pass with four placeholders.
        for pet in companions.values {
            guard let frame = try PetSpriteSheet(package: pet).frames(for: .idle).first,
                  !frame.representations.isEmpty else { throw PreviewError.noSprite(pet.displayName) }
        }

        var openedTaskIDs: [String] = []
        var overviewOpens = 0
        let strip = PetTaskStripView(frame: .zero)
        strip.update(tasks: tasks, petsByTask: companions, overflowCount: 3, attentionOverflowCount: 1,
                     onOpenTask: { openedTaskIDs.append($0.id) },
                     onOpenOverview: { overviewOpens += 1 })

        let hostSize = NSSize(width: strip.preferredWidth + 24, height: 40)
        let host = StripPreviewBackground(frame: NSRect(origin: .zero, size: hostSize))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.dark = dark
        strip.frame = NSRect(x: 12, y: 9, width: strip.preferredWidth, height: 22)
        host.addSubview(strip)
        host.layoutSubtreeIfNeeded()
        strip.layoutSubtreeIfNeeded()
        // A windowless AppKit hierarchy may defer layout despite that request.
        // Run the production strip's layout explicitly before checking its cells.
        strip.layout()
        guard strip.window == nil else { throw PreviewError.unexpectedWindow }

        // Exercise the same accessible controls as the product. Callbacks below
        // only record synthetic task IDs; no URL or app launch is reachable.
        let buttons = (strip.accessibilityChildren() ?? []).compactMap { $0 as? NSButton }
            .filter { !$0.isHidden }.sorted { $0.frame.minX < $1.frame.minX }
        guard buttons.count == tasks.count + 2 else { throw PreviewError.accessibilityChildren }
        for button in buttons {
            let label = button.accessibilityLabel() ?? ""
            guard button.accessibilityRole() == .button else {
                throw PreviewError.inaccessibleButton("\(label): role is \(String(describing: button.accessibilityRole())).")
            }
            guard !label.isEmpty else { throw PreviewError.inaccessibleButton("A button has no accessible label.") }
            guard button.isEnabled, button.acceptsFirstResponder else {
                throw PreviewError.inaccessibleButton("\(label): enabled=\(button.isEnabled), focusable=\(button.acceptsFirstResponder).")
            }
            guard button.frame.width > 0, button.frame.height == 22 else {
                throw PreviewError.inaccessibleButton("\(label): unexpected frame \(NSStringFromRect(button.frame)).")
            }
            guard button.accessibilityPerformPress() else {
                throw PreviewError.inaccessibleButton("\(label): accessibility press was rejected.")
            }
        }
        guard openedTaskIDs == tasks.map(\.id), overviewOpens == 2 else {
            throw PreviewError.wrongActionRouting
        }

        let scale = 2
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(hostSize.width) * scale,
            pixelsHigh: Int(hostSize.height) * scale, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: Int(hostSize.width) * scale * 4, bitsPerPixel: 32
        ) else { throw PreviewError.renderFailed }
        bitmap.size = hostSize
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw PreviewError.renderFailed
        }
        try png.write(to: url, options: .atomic)
    }

    private static func task(
        _ id: String, title: String, provider: PetTaskProviderPresentation, state: PetTaskStatePresentation
    ) -> PetTaskPresentation {
        PetTaskPresentation(id: "\(provider.rawValue):\(id)", sourceID: id, navigationSourceID: id,
                            title: title, summary: "Synthetic strip preview", provider: provider,
                            state: state, deepLinkURL: nil, projectURL: nil)
    }

    private enum PreviewError: LocalizedError {
        case noPets
        case noSprite(String)
        case unexpectedWindow
        case accessibilityChildren
        case inaccessibleButton(String)
        case wrongActionRouting
        case renderFailed

        var errorDescription: String? {
            switch self {
            case .noPets: "The strip preview needs at least one valid pet in CODEX_HOME/pets."
            case let .noSprite(name): "Could not render the installed pet: \(name)."
            case .unexpectedWindow: "The strip preview unexpectedly joined a window."
            case .accessibilityChildren: "The strip must expose four task buttons, overflow, and overview to accessibility."
            case let .inaccessibleButton(detail): "Strip accessibility check failed: \(detail)"
            case .wrongActionRouting: "Strip buttons did not route four tasks and two overview actions correctly."
            case .renderFailed: "Could not render the task pet strip PNG."
            }
        }
    }
}

@MainActor
private final class StripPreviewBackground: NSView {
    var dark = false

    override func draw(_ dirtyRect: NSRect) {
        (dark ? NSColor(white: 0.12, alpha: 1) : .windowBackgroundColor).setFill()
        bounds.fill()
    }
}

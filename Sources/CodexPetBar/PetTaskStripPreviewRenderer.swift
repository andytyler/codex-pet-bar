import AppKit
import ImageIO
import UniformTypeIdentifiers
import CodexPetBarCore

/// An offscreen render of the production strip, with synthetic navigation only.
/// The strip never joins a window, so its animation timer cannot start.
@MainActor
enum PetTaskStripPreviewRenderer {
    static func render(to url: URL, dark: Bool = false, animated: Bool = false,
                       attention: Bool = false, hovered: Bool = false) throws {
        let pets = PetLibrary(petsDirectory: CodexEnvironment.homeDirectory()
            .appendingPathComponent("pets", isDirectory: true)).loadPetsWithDiagnostics().pets
        guard !pets.isEmpty else { throw PreviewError.noPets }

        var tasks = [
            task("approve-release", title: "Prepare the release", provider: .codex, state: attention ? .waiting : .running),
            task("review-settings", title: "Update the settings", provider: .claude, state: attention ? .failed : .running),
            task("keyboard-check", title: "Check keyboard navigation", provider: .cursor, state: .running),
            task("task-sidebar", title: "Build the task sidebar", provider: .codex, state: .running),
        ]
        let preferred = ["boo", "clippy", "mini-gandalf-the-grey", "grumble"].compactMap { id in pets.first { $0.id == id } }
        let previewPets = preferred.count == 4 ? preferred : pets
        let companions = Dictionary(uniqueKeysWithValues: tasks.enumerated().map {
            ($0.element.id, previewPets[$0.offset % previewPets.count])
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
            .filter { !$0.isHidden }
        guard buttons.count == tasks.count + 1 else { throw PreviewError.accessibilityChildren }
        for button in buttons {
            let label = button.accessibilityLabel() ?? ""
            guard button.accessibilityRole() == .button else {
                throw PreviewError.inaccessibleButton("\(label): role is \(String(describing: button.accessibilityRole())).")
            }
            guard !label.isEmpty else { throw PreviewError.inaccessibleButton("A button has no accessible label.") }
            guard button.isEnabled, button.acceptsFirstResponder, button.acceptsFirstMouse(for: nil) else {
                throw PreviewError.inaccessibleButton("\(label): enabled=\(button.isEnabled), focusable=\(button.acceptsFirstResponder).")
            }
            guard button.frame.width > 0, button.frame.height == 22 else {
                throw PreviewError.inaccessibleButton("\(label): unexpected frame \(NSStringFromRect(button.frame)).")
            }
            guard button.accessibilityPerformPress() else {
                throw PreviewError.inaccessibleButton("\(label): accessibility press was rejected.")
            }
        }
        guard Set(openedTaskIDs) == Set(tasks.map(\.id)), openedTaskIDs.count == tasks.count, overviewOpens == 1 else {
            throw PreviewError.wrongActionRouting
        }

        // Verify the background owns a whole click and does not fire when a
        // press is cancelled outside. Accessibility presses alone miss this path.
        let point = strip.convert(NSPoint(x: 170, y: 11), to: nil)
        guard strip.acceptsFirstMouse(for: nil),
              let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
                timestamp: 0.1, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 0),
              let outside = NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: -100, y: -100), modifierFlags: [],
                timestamp: 0.1, windowNumber: 0, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)
        else { throw PreviewError.wrongActionRouting }
        strip.mouseUp(with: up)
        guard overviewOpens == 1 else { throw PreviewError.wrongActionRouting }
        strip.mouseDown(with: down)
        strip.mouseUp(with: up)
        guard overviewOpens == 2 else { throw PreviewError.wrongActionRouting }
        strip.mouseDown(with: down)
        strip.mouseUp(with: outside)
        guard overviewOpens == 2 else { throw PreviewError.wrongActionRouting }

        if hovered, let event = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
            trackingNumber: 0, userData: nil) {
            buttons.first?.mouseEntered(with: event)
        }

        if animated {
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 108, nil) else {
                throw PreviewError.renderFailed
            }
            CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary:
                [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            let initialPositions = Array(buttons.prefix(tasks.count)).map(\.frame.origin.x)
            var idlePositions: [CGFloat] = []
            for frame in 0..<108 {
                if frame == 72 {
                    let runningPositions = Array(buttons.prefix(tasks.count)).map(\.frame.origin.x)
                    guard runningPositions != initialPositions else { throw PreviewError.motionDidNotAdvance }
                    tasks = tasks.map {
                        task($0.sourceID, title: $0.title, provider: $0.provider, state: .recent)
                    }
                    strip.update(tasks: tasks, petsByTask: companions, overflowCount: 0, attentionOverflowCount: 0,
                        onOpenTask: { _ in }, onOpenOverview: {})
                    idlePositions = Array(buttons.prefix(tasks.count)).map(\.frame.origin.x)
                }
                // Same 24 Hz motion stepping as the app, captured at 12 fps.
                strip.advancePreview(deltaTime: 1.0 / 24)
                strip.advancePreview(deltaTime: 1.0 / 24)
                if frame >= 72 {
                    guard Array(buttons.prefix(tasks.count)).map(\.frame.origin.x) == idlePositions else {
                        throw PreviewError.idleDidNotStop
                    }
                }
                let bitmap = try capture(host: host, size: hostSize)
                guard let cgImage = bitmap.cgImage else { throw PreviewError.renderFailed }
                CGImageDestinationAddImage(destination, cgImage, [kCGImagePropertyGIFDictionary:
                    [kCGImagePropertyGIFDelayTime: 1.0 / 12, kCGImagePropertyGIFUnclampedDelayTime: 1.0 / 12]] as CFDictionary)
            }
            guard CGImageDestinationFinalize(destination) else { throw PreviewError.renderFailed }
        } else {
            let bitmap = try capture(host: host, size: hostSize)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw PreviewError.renderFailed }
            try png.write(to: url, options: .atomic)
        }
    }

    private static func capture(host: NSView, size: NSSize) throws -> NSBitmapImageRep {
        let scale = 2
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale,
            pixelsHigh: Int(size.height) * scale, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: Int(size.width) * scale * 4, bitsPerPixel: 32
        ) else { throw PreviewError.renderFailed }
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
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
        case motionDidNotAdvance
        case idleDidNotStop

        var errorDescription: String? {
            switch self {
            case .noPets: "The strip preview needs at least one valid pet in CODEX_HOME/pets."
            case let .noSprite(name): "Could not render the installed pet: \(name)."
            case .unexpectedWindow: "The strip preview unexpectedly joined a window."
            case .accessibilityChildren: "The strip must expose four task buttons and one overview to accessibility."
            case let .inaccessibleButton(detail): "Strip accessibility check failed: \(detail)"
            case .wrongActionRouting: "Strip buttons did not route four tasks and one overview action correctly."
            case .renderFailed: "Could not render the shared pet preview."
            case .motionDidNotAdvance: "Working pets did not move in the shared playfield."
            case .idleDidNotStop: "Idle pets continued moving."
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

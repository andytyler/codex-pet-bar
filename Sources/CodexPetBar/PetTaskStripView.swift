import AppKit
import CodexPetBarCore

/// Several task companions inside one status item, with one route to the full list.
@MainActor
final class PetTaskStripView: NSView {
    private static let cellWidth: CGFloat = 40
    private static let overviewWidth: CGFloat = 18
    private static let overflowWidth: CGFloat = 30
    private var taskButtons: [PetTaskStripButton] = []
    private let overflowButton = PetTaskStripButton(frame: .zero)
    private let overviewButton = PetTaskStripButton(frame: .zero)
    private var cachedSheets: [SheetKey: PreparedSheet] = [:]
    private var animationTimer: Timer?
    private var animationStep = 0
    private var observing = false
    private var screenSleeping = false
    private var hasOverflow = false

    var preferredWidth: CGFloat {
        CGFloat(taskButtons.count) * Self.cellWidth + Self.overviewWidth
            + (hasOverflow ? Self.overflowWidth : 0)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: preferredWidth, height: 22)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureOverview()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureOverview()
    }

    isolated deinit {
        stopAnimation()
        stopObserving()
    }

    func update(
        tasks: [PetTaskPresentation],
        petsByTask: [String: PetPackage],
        overflowCount: Int,
        attentionOverflowCount: Int,
        onOpenTask: @escaping (PetTaskPresentation) -> Void,
        onOpenOverview: @escaping () -> Void
    ) {
        var seen = Set<String>()
        let visibleTasks = Array(tasks.filter { seen.insert($0.id).inserted }.prefix(4))
        let oldButtons = Dictionary(uniqueKeysWithValues: taskButtons.map { ($0.taskID, $0) })
        var visibleSheetKeys = Set<SheetKey>()
        taskButtons = visibleTasks.map { task in
            let button = oldButtons[task.id] ?? PetTaskStripButton(frame: .zero)
            button.taskID = task.id
            let pet = petsByTask[task.id]
            let frames: [NSImage]
            if let pet {
                let key = SheetKey(pet: pet)
                visibleSheetKeys.insert(key)
                if cachedSheets[key] == nil {
                    cachedSheets[key] = PreparedSheet(package: pet)
                }
                frames = cachedSheets[key]?.frames(for: task.state) ?? []
            } else {
                frames = []
            }
            button.spriteFrames = frames
            button.displayMode = .pet(task.state)
            button.toolTip = "\(pet?.displayName ?? "Task companion")\n\(task.title)\n\(task.state.displayName)"
            button.setAccessibilityLabel("\(pet?.displayName ?? "Companion"), \(task.title), \(task.state.displayName)")
            button.setAccessibilityHelp(task.accessibilityOpenHint)
            button.onPress = { onOpenTask(task) }
            button.onSecondaryPress = onOpenOverview
            button.showFrame(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : animationStep)
            if button.superview !== self { addSubview(button) }
            return button
        }
        let displayedIDs = Set(taskButtons.map(\.taskID))
        for button in oldButtons.values where !displayedIDs.contains(button.taskID) {
            button.removeFromSuperview()
        }
        cachedSheets = cachedSheets.filter { visibleSheetKeys.contains($0.key) }

        let hiddenCount = max(0, overflowCount) + max(0, seen.count - visibleTasks.count)
        hasOverflow = hiddenCount > 0
        overflowButton.isHidden = !hasOverflow
        overflowButton.displayMode = .overflow(hiddenCount, needsAttention: attentionOverflowCount > 0)
        overflowButton.onPress = onOpenOverview
        overflowButton.onSecondaryPress = onOpenOverview
        let attentionHint = attentionOverflowCount > 0 ? ", \(attentionOverflowCount) need attention" : ""
        overflowButton.toolTip = "\(hiddenCount) more active tasks\(attentionHint)"
        overflowButton.setAccessibilityLabel("Show \(hiddenCount) more active tasks\(attentionHint)")
        overviewButton.onPress = onOpenOverview
        overviewButton.onSecondaryPress = onOpenOverview
        overviewButton.setAccessibilityLabel("Show all tasks and Pet Bar controls")
        setAccessibilityChildren(taskButtons + (hasOverflow ? [overflowButton] : []) + [overviewButton])
        needsLayout = true
        invalidateIntrinsicContentSize()
        updateAnimation()
    }

    override func layout() {
        super.layout()
        var x: CGFloat = 0
        for button in taskButtons {
            button.frame = NSRect(x: x, y: 0, width: Self.cellWidth, height: bounds.height)
            x += Self.cellWidth
        }
        if hasOverflow {
            overflowButton.frame = NSRect(x: x, y: 0, width: Self.overflowWidth, height: bounds.height)
            x += Self.overflowWidth
        }
        overviewButton.frame = NSRect(x: x, y: 0, width: Self.overviewWidth, height: bounds.height)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { startObserving() } else { stopObserving() }
        updateAnimation()
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview == nil {
            stopAnimation()
            stopObserving()
        }
        super.viewWillMove(toSuperview: newSuperview)
    }

    override var isHidden: Bool {
        didSet { updateAnimation() }
    }

    override func viewDidHide() {
        super.viewDidHide()
        stopAnimation()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        updateAnimation()
    }

    fileprivate func focusButton(after button: PetTaskStripButton, direction: Int) {
        let buttons = taskButtons + (hasOverflow ? [overflowButton] : []) + [overviewButton]
        guard let index = buttons.firstIndex(where: { $0 === button }), !buttons.isEmpty else { return }
        let next = (index + direction + buttons.count) % buttons.count
        window?.makeFirstResponder(buttons[next])
    }

    private func configureOverview() {
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Task companions")
        setAccessibilityHelp("Choose a companion to open its task, or show all tasks and Pet Bar controls.")
        overviewButton.displayMode = .overview
        overviewButton.toolTip = "Show all tasks and Pet Bar controls"
        overflowButton.isHidden = true
        addSubview(overflowButton)
        addSubview(overviewButton)
        setAccessibilityChildren([overviewButton])
    }

    private func updateAnimation() {
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let shouldAnimate = window != nil && window?.isVisible == true && !isHiddenOrHasHiddenAncestor
            && !screenSleeping && !reduced && taskButtons.contains { $0.animates }
        guard shouldAnimate else {
            stopAnimation()
            if reduced { taskButtons.forEach { $0.showFrame(0) } }
            return
        }
        guard animationTimer == nil else { return }
        let timer = Timer(timeInterval: 0.125, repeats: true) { [weak self] timer in
            let hasOwner = MainActor.assumeIsolated {
                guard let self else { return false }
                self.animationStep &+= 1
                self.taskButtons.filter(\.animates).forEach { $0.showFrame(self.animationStep) }
                return true
            }
            if !hasOwner { timer.invalidate() }
        }
        timer.tolerance = 0.025
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func startObserving() {
        guard !observing else { return }
        observing = true
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(displayOptionsChanged),
                              name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            workspace.addObserver(self, selector: #selector(screenDidSleep), name: name, object: nil)
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspace.addObserver(self, selector: #selector(screenDidWake), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(displayOptionsChanged),
                                              name: NSWindow.didChangeOcclusionStateNotification, object: nil)
    }

    private func stopObserving() {
        guard observing else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        observing = false
    }

    @objc private func displayOptionsChanged() { updateAnimation() }
    @objc private func screenDidSleep() { screenSleeping = true; stopAnimation() }
    @objc private func screenDidWake() { screenSleeping = false; updateAnimation() }

    private struct SheetKey: Hashable {
        let id: String
        let url: URL
        let version: Int

        init(pet: PetPackage) {
            id = pet.id
            url = pet.spritesheetURL
            version = pet.spriteVersionNumber
        }
    }

    private final class PreparedSheet {
        private let sheet: PetSpriteSheet?
        private var preparedFrames: [PetAnimationState: [NSImage]] = [:]

        init(package: PetPackage) {
            sheet = try? PetSpriteSheet(package: package)
        }

        func frames(for state: PetTaskStatePresentation) -> [NSImage] {
            let animation: PetAnimationState = switch state {
            case .running: .running
            case .waiting: .waiting
            case .failed: .failed
            case .completed, .recent: .idle
            }
            if let prepared = preparedFrames[animation] { return prepared }
            let originals = sheet?.frames(for: animation) ?? []
            let images = originals.compactMap { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) }
            // Share the same transparent-padding trim for every frame of a state.
            // Nothing visible is cropped and the companion does not change size as it moves.
            let envelope = images.compactMap(Self.alphaBounds).reduce(CGRect.null) { $0.union($1) }
            let rendered = images.compactMap { Self.menuImage($0, envelope: envelope) }
            preparedFrames[animation] = rendered
            return rendered
        }

        private static func alphaBounds(_ image: CGImage) -> CGRect? {
            guard image.bitsPerPixel == 32, image.alphaInfo == .premultipliedLast,
                  image.bitmapInfo.contains(.byteOrder32Big), let data = image.dataProvider?.data,
                  let bytes = CFDataGetBytePtr(data) else {
                return CGRect(x: 0, y: 0, width: image.width, height: image.height)
            }
            var minX = image.width, minY = image.height, maxX = -1, maxY = -1
            for y in 0..<image.height {
                for x in 0..<image.width where bytes[y * image.bytesPerRow + x * 4 + 3] > 0 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            guard maxX >= minX, maxY >= minY else { return nil }
            return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
                .insetBy(dx: -1, dy: -1)
                .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }

        private static func menuImage(_ image: CGImage, envelope: CGRect) -> NSImage? {
            guard !envelope.isNull, let cropped = image.cropping(to: envelope) else { return nil }
            let size = NSSize(width: 32, height: 22)
            let output = NSImage(size: size)
            output.isTemplate = false
            for scale in [1, 2] {
                guard let context = CGContext(data: nil, width: Int(size.width) * scale,
                    height: Int(size.height) * scale, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
                context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
                context.interpolationQuality = .high
                let factor = min(30 / envelope.width, 21 / envelope.height)
                let artSize = NSSize(width: envelope.width * factor, height: envelope.height * factor)
                context.draw(cropped, in: CGRect(x: (size.width - artSize.width) / 2,
                                                y: (size.height - artSize.height) / 2,
                                                width: artSize.width, height: artSize.height))
                guard let bitmap = context.makeImage() else { continue }
                let representation = NSBitmapImageRep(cgImage: bitmap)
                representation.size = size
                output.addRepresentation(representation)
            }
            return output.representations.isEmpty ? nil : output
        }
    }
}

@MainActor
private final class PetTaskStripButton: NSButton {
    enum DisplayMode {
        case pet(PetTaskStatePresentation)
        case overflow(Int, needsAttention: Bool)
        case overview
    }

    var taskID = ""
    var spriteFrames: [NSImage] = []
    var displayMode: DisplayMode = .overview { didSet { needsDisplay = true } }
    var onPress: (() -> Void)?
    var onSecondaryPress: (() -> Void)?
    private var frameIndex = 0
    private var hovered = false
    private var hoverTracking: NSTrackingArea?

    var animates: Bool {
        if case let .pet(state) = displayMode { return state.isActive && spriteFrames.count > 1 }
        return false
    }

    override var acceptsFirstResponder: Bool { true }
    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 2, dy: 1) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        title = ""
        isBordered = false
        focusRingType = .exterior
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setButtonType(.momentaryChange)
        target = self
        action = #selector(pressed)
    }

    func showFrame(_ step: Int) {
        let next = spriteFrames.isEmpty ? 0 : step % spriteFrames.count
        guard next != frameIndex || needsDisplay else { return }
        frameIndex = next
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovered || isHighlighted {
            NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.14 : 0.07).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5).fill()
        }
        switch displayMode {
        case let .pet(state):
            if !spriteFrames.isEmpty {
                let image = spriteFrames[min(frameIndex, spriteFrames.count - 1)]
                let height = min(22, bounds.height)
                image.draw(in: NSRect(x: (bounds.width - 32) / 2 - 1, y: (bounds.height - height) / 2,
                                      width: 32, height: height),
                           from: .zero, operation: .sourceOver, fraction: 1)
            } else {
                drawSymbol("pawprint.fill", size: 14, color: .secondaryLabelColor)
            }
            let color: NSColor = switch state {
            case .waiting: .systemOrange
            case .failed: .systemRed
            case .running: .systemBlue
            case .completed, .recent: .tertiaryLabelColor
            }
            color.setFill()
            let marker = NSRect(x: bounds.maxX - 7, y: 3, width: 4, height: 4)
            NSBezierPath(ovalIn: marker).fill()
        case let .overflow(count, needsAttention):
            let label = "+\(count)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: needsAttention ? NSColor.systemOrange : NSColor.labelColor,
            ]
            let size = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                   y: (bounds.height - size.height) / 2), withAttributes: attributes)
        case .overview:
            drawSymbol("chevron.down", size: 9, color: .labelColor)
        }
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 5, yRadius: 5).fill()
    }

    override func updateTrackingAreas() {
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTracking = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func rightMouseDown(with event: NSEvent) { onSecondaryPress?() }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled, let onPress else { return false }
        onPress()
        return true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 49, 76: performClick(nil)
        case 123: (superview as? PetTaskStripView)?.focusButton(after: self, direction: -1)
        case 124: (superview as? PetTaskStripView)?.focusButton(after: self, direction: 1)
        default: super.keyDown(with: event)
        }
    }

    private func drawSymbol(_ name: String, size: CGFloat, color: NSColor) {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
                .applying(.init(paletteColors: [color]))) else { return }
        let imageSize = symbol.size
        symbol.draw(in: NSRect(x: (bounds.width - imageSize.width) / 2,
                              y: (bounds.height - imageSize.height) / 2,
                              width: imageSize.width, height: imageSize.height))
    }

    @objc private func pressed() { onPress?() }
}

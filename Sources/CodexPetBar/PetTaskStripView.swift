import AppKit
import CodexPetBarCore

/// One shared playfield: working pets roam, idle pets stay where they stopped.
@MainActor
final class PetTaskStripView: NSView {
    private static let playfieldWidth: CGFloat = 176
    private static let petWidth: CGFloat = 32
    private static let overviewWidth: CGFloat = 26
    private var taskButtons: [PetTaskStripButton] = []
    private let overviewButton = PetTaskStripButton(frame: .zero)
    private var cachedSheets: [SheetKey: PreparedSheet] = [:]
    private var animationTimer: Timer?
    private var playfield = PetSharedPlayfield()
    private var petsByTask: [String: PetPackage] = [:]
    private var statesByTask: [String: PetTaskStatePresentation] = [:]
    private var playfieldTracking: NSTrackingArea?
    private var isPointerInside = false
    private var lastTick: TimeInterval?
    private var onOpenOverview: (() -> Void)?
    private var observing = false
    private var screenSleeping = false

    var preferredWidth: CGFloat {
        Self.playfieldWidth + Self.overviewWidth
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
        self.onOpenOverview = onOpenOverview
        self.petsByTask = petsByTask
        var seen = Set<String>()
        let visibleTasks = Array(tasks.filter { seen.insert($0.id).inserted }.prefix(4))
        statesByTask = Dictionary(uniqueKeysWithValues: visibleTasks.map { ($0.id, $0.state) })
        let oldButtons = Dictionary(uniqueKeysWithValues: taskButtons.map { ($0.taskID, $0) })
        var visibleSheetKeys = Set<SheetKey>()
        taskButtons = visibleTasks.map { task in
            let button = oldButtons[task.id] ?? PetTaskStripButton(frame: .zero)
            button.taskID = task.id
            let pet = petsByTask[task.id]
            if let pet {
                let key = SheetKey(pet: pet)
                visibleSheetKeys.insert(key)
                if cachedSheets[key] == nil { cachedSheets[key] = PreparedSheet(package: pet) }
            }
            button.displayMode = .pet(task.state)
            let stateLabel = task.state.isActive ? task.state.displayName : "Idle"
            let isUnassigned = task.id.hasPrefix("pet-bar:idle:")
            button.toolTip = isUnassigned ? "\(task.title) · Idle\nOpen task list"
                : "\(pet?.displayName ?? "Task companion")\n\(task.title)\n\(stateLabel)"
            button.setAccessibilityLabel("\(pet?.displayName ?? "Companion"), \(task.title), \(stateLabel)")
            button.setAccessibilityHelp(isUnassigned ? "Opens the task list" : task.accessibilityOpenHint)
            button.onPress = { onOpenTask(task) }
            button.onSecondaryPress = onOpenOverview
            if button.superview !== self { addSubview(button) }
            return button
        }
        let displayedIDs = Set(taskButtons.map(\.taskID))
        for button in oldButtons.values where !displayedIDs.contains(button.taskID) {
            button.removeFromSuperview()
        }
        cachedSheets = cachedSheets.filter { visibleSheetKeys.contains($0.key) }
        playfield.update(participants: visibleTasks.map { .init(id: $0.id, moves: $0.state == .running) })

        let hiddenCount = max(0, overflowCount) + max(0, seen.count - visibleTasks.count)
        let attentionHint = attentionOverflowCount > 0 ? ", \(attentionOverflowCount) need attention" : ""
        overviewButton.displayMode = hiddenCount > 0
            ? .overflow(hiddenCount, needsAttention: attentionOverflowCount > 0) : .overview
        overviewButton.onPress = onOpenOverview
        overviewButton.onSecondaryPress = onOpenOverview
        overviewButton.toolTip = hiddenCount > 0
            ? "\(hiddenCount) more active tasks\(attentionHint)" : "Open task list"
        overviewButton.setAccessibilityLabel(hiddenCount > 0
            ? "Show all tasks, \(hiddenCount) more active tasks\(attentionHint)" : "Show all tasks and Pet Bar controls")
        setAccessibilityChildren(taskButtons + [overviewButton])
        needsLayout = true
        invalidateIntrinsicContentSize()
        applyMotion(deltaTime: 0)
        updateAnimation()
    }

    override func layout() {
        super.layout()
        applyMotion(deltaTime: 0)
        overviewButton.frame = NSRect(x: Self.playfieldWidth, y: 0, width: Self.overviewWidth, height: bounds.height)
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
        let buttons = taskButtons + [overviewButton]
        guard let index = buttons.firstIndex(where: { $0 === button }), !buttons.isEmpty else { return }
        let next = (index + direction + buttons.count) % buttons.count
        window?.makeFirstResponder(buttons[next])
    }

    override func updateTrackingAreas() {
        if let playfieldTracking { removeTrackingArea(playfieldTracking) }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        playfieldTracking = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { isPointerInside = true; updateAnimation() }
    override func mouseExited(with event: NSEvent) { isPointerInside = false; updateAnimation() }
    override func mouseUp(with event: NSEvent) { onOpenOverview?() }
    override func rightMouseDown(with event: NSEvent) { onOpenOverview?() }

    /// The preview advances this same production renderer without a live timer.
    func advancePreview(deltaTime: Double) { applyMotion(deltaTime: deltaTime) }

    private func applyMotion(deltaTime: Double) {
        let frames = playfield.step(deltaTime: deltaTime,
            width: Double(Self.playfieldWidth), spriteWidth: Double(Self.petWidth))
        for frame in frames {
            guard let button = taskButtons.first(where: { $0.taskID == frame.id }),
                  let state = statesByTask[frame.id] else { continue }
            let rect = NSRect(x: frame.x, y: 0, width: Self.petWidth, height: max(22, bounds.height))
            if button.frame != rect { button.frame = rect }
            let animation: PetAnimationState
            switch state {
            case .running: animation = frame.facingRight ? .runningRight : .runningLeft
            case .waiting: animation = .waiting
            case .failed: animation = .failed
            case .completed, .recent: animation = .idle
            }
            if let pet = petsByTask[frame.id] {
                button.spriteFrames = cachedSheets[SheetKey(pet: pet)]?.frames(for: animation) ?? []
            } else {
                button.spriteFrames = []
            }
            // Idle means standing still, not a looping idle animation.
            button.showFrame(state == .running ? Int(frame.animationTime * 8) : 0)
        }
    }

    private func configureOverview() {
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Shared pets")
        setAccessibilityHelp("Pets share one space. Working pets move; idle pets stand. Choose a pet to open its task, or open the task list.")
        overviewButton.displayMode = .overview
        overviewButton.toolTip = "Show all tasks and Pet Bar controls"
        addSubview(overviewButton)
        setAccessibilityChildren([overviewButton])
    }

    private func updateAnimation() {
        let shouldAnimate = window != nil && window?.isVisible == true && !isHiddenOrHasHiddenAncestor
            && !screenSleeping && !isPointerInside && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            && statesByTask.values.contains(.running)
        guard shouldAnimate else { stopAnimation(); return }
        guard animationTimer == nil else { return }
        lastTick = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 24, repeats: true) { [weak self] timer in
            let hasOwner = MainActor.assumeIsolated {
                guard let self else { return false }
                let now = ProcessInfo.processInfo.systemUptime
                let delta = now - (self.lastTick ?? now)
                self.lastTick = now
                // Keep moving targets still while someone navigates by keyboard.
                if self.window?.isKeyWindow == true,
                   let focused = self.window?.firstResponder as? NSView, focused.isDescendant(of: self) { return true }
                self.applyMotion(deltaTime: delta)
                return true
            }
            if !hasOwner { timer.invalidate() }
        }
        timer.tolerance = 0.008
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        lastTick = nil
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

        func frames(for animation: PetAnimationState) -> [NSImage] {
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
                                                y: 0.5,
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
    var spriteFrames: [NSImage] = [] { didSet { needsDisplay = true } }
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
                           from: .zero, operation: .sourceOver, fraction: 1,
                           respectFlipped: true, hints: nil)
            } else {
                drawSymbol("pawprint.fill", size: 14, color: .secondaryLabelColor)
            }
            if state == .waiting || state == .failed {
                (state == .failed ? NSColor.systemRed : .systemOrange).setFill()
                NSBezierPath(ovalIn: NSRect(x: bounds.maxX - 5, y: 3, width: 3, height: 3)).fill()
            }
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

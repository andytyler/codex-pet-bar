import AppKit
import CodexPetBarCore

@MainActor
final class StatusPetController: NSObject {
    private let statusItem: NSStatusItem
    private let petLibrary: PetLibrary
    private let preferences: AppPreferences
    private let codexStateURL: URL
    private let transcriptionHistoryURL: URL
    private var pets: [PetPackage] = []
    private var selectedPet: PetPackage?
    private var spriteSheet: PetSpriteSheet?
    private var currentState: PetAnimationState = .waiting
    private var frameIndex = 0
    private var timer: Timer?
    private var lastTranscriptionSize: UInt64?

    init(
        petLibrary: PetLibrary = PetLibrary(petsDirectory: PetLibrary.defaultPetsDirectory()),
        preferences: AppPreferences = AppPreferences(),
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: preferences.petSize.menuBarLength)
        self.petLibrary = petLibrary
        self.preferences = preferences
        self.codexStateURL = codexHome.appendingPathComponent(".codex-global-state.json")
        self.transcriptionHistoryURL = codexHome.appendingPathComponent("transcription-history.jsonl")
        super.init()
    }

    func start() {
        configureButton()
        refreshPets(playReaction: false)
        startTimer()
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            return
        }
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(showMenu)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Codex Pet"
    }

    @objc private func showMenu() {
        statusItem.menu = makeMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.14, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func tick() {
        updateActivityState()
        renderCurrentFrame()
    }

    private func updateActivityState() {
        if let manualState = preferences.manualAnimationState {
            setState(manualState)
            return
        }

        let activity = detectActivity()
        setState(activity.animationState)
    }

    private func detectActivity() -> CodexActivity {
        if didTranscriptionHistoryChange() {
            return .listening
        }

        guard let logModificationDate = try? FileManager.default
            .attributesOfItem(atPath: codexStateURL.path)[.modificationDate] as? Date
        else {
            return .idle
        }

        let age = Date().timeIntervalSince(logModificationDate)
        if age < 20 {
            return .running
        }
        if age < 60 {
            return .reviewing
        }
        return .idle
    }

    private func didTranscriptionHistoryChange() -> Bool {
        guard let size = try? FileManager.default
            .attributesOfItem(atPath: transcriptionHistoryURL.path)[.size] as? UInt64
        else {
            return false
        }

        defer { lastTranscriptionSize = size }
        guard let lastTranscriptionSize else {
            return false
        }
        return size > lastTranscriptionSize
    }

    private func setState(_ state: PetAnimationState) {
        if currentState != state {
            currentState = state
            frameIndex = 0
        }
    }

    private func renderCurrentFrame() {
        guard let frames = spriteSheet?.frames(for: currentState), !frames.isEmpty else {
            statusItem.button?.image = fallbackImage()
            return
        }

        let image = scaledImage(frames[frameIndex % frames.count], length: preferences.petSize.menuBarLength)
        statusItem.length = preferences.petSize.menuBarLength
        statusItem.button?.image = image
        frameIndex = (frameIndex + 1) % frames.count
    }

    private func refreshPets(playReaction: Bool) {
        pets = petLibrary.loadPets()
        let codexSelectedPetID = readCodexSelectedPetID()
        selectedPet = PetSelection.resolve(
            pets: pets,
            preferences: preferences,
            codexSelectedPetID: codexSelectedPetID
        )
        loadSelectedPet()
        if playReaction {
            setState(.waving)
        }
    }

    private func readCodexSelectedPetID() -> String? {
        guard let data = try? Data(contentsOf: codexStateURL) else {
            return nil
        }
        return try? CodexGlobalState.selectedPetID(from: data)
    }

    private func loadSelectedPet() {
        guard let selectedPet else {
            spriteSheet = nil
            return
        }

        do {
            spriteSheet = try PetSpriteSheet(package: selectedPet)
        } catch {
            spriteSheet = nil
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let title = selectedPet?.displayName ?? "No Codex Pet"
        let titleItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        let petsMenu = NSMenu()
        if pets.isEmpty {
            let item = NSMenuItem(title: "No pets found", action: nil, keyEquivalent: "")
            item.isEnabled = false
            petsMenu.addItem(item)
        } else {
            for pet in pets {
                let item = NSMenuItem(title: pet.displayName, action: #selector(selectPet(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = pet.id
                item.state = pet.id == selectedPet?.id ? .on : .off
                petsMenu.addItem(item)
            }
        }
        let petsItem = NSMenuItem(title: "Pets", action: nil, keyEquivalent: "")
        menu.setSubmenu(petsMenu, for: petsItem)
        menu.addItem(petsItem)

        let followItem = NSMenuItem(title: "Follow Codex Pet", action: #selector(toggleFollowCodexPet), keyEquivalent: "")
        followItem.target = self
        followItem.state = preferences.followCodexPet ? .on : .off
        menu.addItem(followItem)

        let sizeMenu = NSMenu()
        for size in PetSize.allCases {
            let item = NSMenuItem(title: size.rawValue.capitalized, action: #selector(selectSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = size.rawValue
            item.state = size == preferences.petSize ? .on : .off
            sizeMenu.addItem(item)
        }
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        menu.setSubmenu(sizeMenu, for: sizeItem)
        menu.addItem(sizeItem)

        let stateMenu = NSMenu()
        let automaticItem = NSMenuItem(title: "Automatic", action: #selector(selectAutomaticState), keyEquivalent: "")
        automaticItem.target = self
        automaticItem.state = preferences.manualAnimationState == nil ? .on : .off
        stateMenu.addItem(automaticItem)
        for state in PetAnimationState.allCases {
            let item = NSMenuItem(title: state.rawValue, action: #selector(selectState(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = state.rawValue
            item.state = state == preferences.manualAnimationState ? .on : .off
            stateMenu.addItem(item)
        }
        let stateItem = NSMenuItem(title: "State", action: nil, keyEquivalent: "")
        menu.setSubmenu(stateMenu, for: stateItem)
        menu.addItem(stateItem)

        menu.addItem(.separator())
        let refreshItem = NSMenuItem(title: "Refresh Pets", action: #selector(refreshPetsFromMenu), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let openPetsItem = NSMenuItem(title: "Open Pets Folder", action: #selector(openPetsFolder), keyEquivalent: "")
        openPetsItem.target = self
        menu.addItem(openPetsItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func selectPet(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else {
            return
        }
        preferences.followCodexPet = false
        preferences.selectedPetIDOverride = id
        refreshPets(playReaction: true)
    }

    @objc private func toggleFollowCodexPet() {
        preferences.followCodexPet.toggle()
        refreshPets(playReaction: true)
    }

    @objc private func selectSize(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let size = PetSize(rawValue: rawValue)
        else {
            return
        }
        preferences.petSize = size
        statusItem.length = size.menuBarLength
        renderCurrentFrame()
    }

    @objc private func selectAutomaticState() {
        preferences.manualAnimationState = nil
    }

    @objc private func selectState(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let state = PetAnimationState(rawValue: rawValue)
        else {
            return
        }
        preferences.manualAnimationState = state
        setState(state)
    }

    @objc private func refreshPetsFromMenu() {
        refreshPets(playReaction: true)
    }

    @objc private func openPetsFolder() {
        NSWorkspace.shared.open(petLibrary.petsDirectory)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func scaledImage(_ image: NSImage, length: Double) -> NSImage {
        let targetHeight = min(length, 22)
        let targetWidth = targetHeight * (Double(PetAtlasMetadata.cellWidth) / Double(PetAtlasMetadata.cellHeight))
        let targetSize = NSSize(width: targetWidth, height: targetHeight)
        let output = NSImage(size: targetSize)
        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        image.draw(in: NSRect(origin: .zero, size: targetSize))
        output.unlockFocus()
        output.isTemplate = false
        return output
    }

    private func fallbackImage() -> NSImage {
        let image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Codex Pet")
            ?? NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        return image
    }
}

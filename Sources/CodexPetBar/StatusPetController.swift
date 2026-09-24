import AppKit
import CodexPetBarCore
import Darwin

@MainActor
final class StatusPetController: NSObject {
    private let statusItem: NSStatusItem
    private let hoverPanelController = PetHoverPanelController()
    private let loginItemController = LoginItemController()
    private let petLibrary: PetLibrary
    private let preferences: AppPreferences
    private let codexStateURL: URL
    private let petEventsURL: URL
    private let sessionIndexURL: URL
    private let sessionsRootURL: URL
    private var pets: [PetPackage] = []
    private var petLoadIssues: [PetLoadIssue] = []
    private var selectedPet: PetPackage?
    private var spriteSheet: PetSpriteSheet?
    private var selectedPetLoadError: String?
    private var currentState: PetAnimationState = .waiting
    private var lastRenderKey: RenderKey?
    private var lastAppliedStatusLength: Double?
    private var manualFrameClock = PetAnimationFrameClock()
    private var runtime: PetRuntime?
    private var runtimeLayout: PetRuntimeLayout?
    private var timer: Timer?
    private var currentTimerInterval: TimeInterval?
    private var lastFrameDate: Date?
    private var petEventOffset: UInt64 = 0
    private var petEventLogWasReplaced = false
    private var cachedPetEvents: [CodexPetEvent]?
    private var lastHookSnapshotRefreshDate = Date.distantPast
    private var currentActivity: CodexActivity = .idle
    private var approvalRequestedForNextFrame = false
    private var attentionPresentations = PetAttentionPresentationQueue()
    private var attentionPresentationWasActive = false
    private var attentionRepeatCooldownRemaining: Double = 0
    private var reducedMotionAttentionRemaining: Double = 0
    private var reactionState: PetAnimationState?
    private var reactionRemaining: Double = 0
    private var completionTracker = PetTaskCompletionTracker()
    private var completionVisibleUntil: Date?
    private var isInstallingHooks = false
    private lazy var fallbackPetImage: NSImage = {
        let image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Codex Pet")
            ?? NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        return image
    }()
    private var isDisplayingFallback = false
    private var staticImageCache: [StaticImageKey: NSImage] = [:]
    private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private var runningThreadCount = 0
    private var activeSessionIDs: Set<String> = []
    private var activeScopes: [CodexPetActiveScope] = []
    private var verifiedRunningCodexScopes: [CodexRolloutActivityScope] = []
    private var verifiedCompletedCodexScopes: [CodexRolloutActivityScope] = []
    private var lastRolloutActivityScanDate = Date.distantPast
    private var threadDotPhase: Double = 0
    private var petEventFileSource: DispatchSourceFileSystemObject?
    private var codexStateFileSource: DispatchSourceFileSystemObject?
    private var codexStateWatchGeneration = 0
    private var sessionIndexFileSource: DispatchSourceFileSystemObject?
    private var petEventDebounceTask: Task<Void, Never>?
    private var petEventReloadTask: Task<Void, Never>?
    private var codexStateDebounceTask: Task<Void, Never>?
    private var rolloutActivityScanTask: Task<Void, Never>?
    private var lastCodexSelectedPetID: String?
    private var cachedThreadIndexSignature: ThreadIndexSignature?
    private var cachedRecentThreads: [CodexThreadSummary] = []
    private var cachedTaskSourceSummaries: [PetTaskSummary] = []
    private var cachedTaskSummaries: [PetTaskSummary] = []
    private var taskSummaryRefreshTask: Task<Void, Never>?
    private var taskSummariesDirty = true
    private var threadBadgeImageCache: [Bool: NSImage] = [:]
    private var cursorGazeLocalMonitor: Any?
    private var cursorGazeGlobalMonitor: Any?
    private var cursorGazeWorkItem: DispatchWorkItem?
    private var cursorGazeMonitoringActive = false
    private var cursorGazeGeneration = 0
    private var pendingCursorLocation: NSPoint?
    private var cursorGazeHeadingIndex: Int?
    private var lastCursorGazeRenderTime: TimeInterval?

    init(
        petLibrary: PetLibrary? = nil,
        preferences: AppPreferences = AppPreferences(),
        codexHome: URL = CodexEnvironment.homeDirectory()
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: preferences.petSize.menuBarLength)
        self.petLibrary = petLibrary ?? PetLibrary(
            petsDirectory: codexHome.appendingPathComponent("pets", isDirectory: true)
        )
        self.preferences = preferences
        self.codexStateURL = codexHome.appendingPathComponent(".codex-global-state.json")
        self.petEventsURL = codexHome.appendingPathComponent("pet-events.jsonl")
        self.sessionIndexURL = codexHome.appendingPathComponent("session_index.jsonl")
        self.sessionsRootURL = codexHome.appendingPathComponent("sessions", isDirectory: true)
        super.init()
        self.lastAppliedStatusLength = preferences.petSize.menuBarLength
    }

    isolated deinit {
        if let cursorGazeLocalMonitor {
            NSEvent.removeMonitor(cursorGazeLocalMonitor)
        }
        if let cursorGazeGlobalMonitor {
            NSEvent.removeMonitor(cursorGazeGlobalMonitor)
        }
        cursorGazeWorkItem?.cancel()
        taskSummaryRefreshTask?.cancel()
        petEventDebounceTask?.cancel()
        petEventReloadTask?.cancel()
        rolloutActivityScanTask?.cancel()
        petEventFileSource?.cancel()
        codexStateFileSource?.cancel()
        sessionIndexFileSource?.cancel()
    }

    func start() {
        try? FileManager.default.createDirectory(
            at: petLibrary.petsDirectory,
            withIntermediateDirectories: true
        )
        configureButton()
        refreshPets(playReaction: false)
        updateHookActivitySnapshot(now: Date())
        refreshTaskSummariesInBackground()
        startCodexStateFileWatcherIfAvailable()
        startSessionIndexFileWatcherIfAvailable()
        scheduleRolloutActivityScan()
        startAccessibilityObserver()
        updateCursorGazeMonitoring()
        renderCurrentFrame(deltaTime: 0)
        startTimer()
    }

    func offerOpenAtLoginIfNeeded() {
        loginItemController.promptOnFirstLaunch()
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            return
        }
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.target = self
        button.action = #selector(showMenu)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        hoverPanelController.attach(
            to: button,
            contentProvider: { [weak self] in
                self?.hoverPanelContent() ?? PetHoverPanelContent(
                    petName: "Codex Pet",
                    statusText: "Idle",
                    projects: []
                )
            },
            onOpenTask: { [weak self] task in
                self?.openPresentedTask(task)
            }
        )
        updateStatusDescription()

        if ProcessInfo.processInfo.arguments.contains("--preview-task-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.hoverPanelController.presentPreview()
            }
        }
    }

    @objc private func showMenu() {
        hoverPanelController.menuWillOpen()
        defer {
            hoverPanelController.menuDidClose()
        }
        statusItem.menu = makeMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func startTimer() {
        let interval = desiredTimerInterval()
        timer?.invalidate()
        currentTimerInterval = interval
        let timer = Timer(
            timeInterval: interval,
            target: self,
            selector: #selector(timerDidFire(_:)),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = interval * 0.25
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func timerDidFire(_ timer: Timer) {
        tick()
    }

    private func tick() {
        let now = Date()
        let deltaTime = frameDeltaTime(now: now)
        expireCompletion(now: now)
        advanceReaction(deltaTime: deltaTime)
        updateThreadDots(deltaTime: deltaTime)
        refreshHookActivityForExpiryIfNeeded(now: now)
        refreshRolloutActivityIfNeeded(now: now)
        renderCurrentFrame(deltaTime: deltaTime)
        updateTimerCadenceIfNeeded()
    }

    private func startPetEventFileWatcherIfAvailable() {
        guard FileManager.default.fileExists(atPath: petEventsURL.path) else {
            petEventFileSource?.cancel()
            petEventFileSource = nil
            return
        }

        petEventFileSource?.cancel()
        petEventFileSource = fileSystemSource(
            url: petEventsURL,
            eventMask: [.write, .extend, .attrib, .delete, .rename]
        ) { [weak self] event in
            guard let self else {
                return
            }

            if !event.intersection([.delete, .rename]).isEmpty {
                self.petEventFileSource?.cancel()
                self.petEventFileSource = nil
                self.petEventOffset = 0
                self.petEventLogWasReplaced = true
            }
            self.schedulePetEventLogProcessing()
        }
    }

    private func startCodexStateFileWatcherIfAvailable() {
        codexStateWatchGeneration &+= 1
        let generation = codexStateWatchGeneration
        guard FileManager.default.fileExists(atPath: codexStateURL.path) else {
            codexStateFileSource?.cancel()
            codexStateFileSource = nil
            return
        }

        codexStateFileSource?.cancel()
        codexStateFileSource = fileSystemSource(
            url: codexStateURL,
            eventMask: [.write, .extend, .attrib, .delete, .rename]
        ) { [weak self] event in
            guard let self, generation == self.codexStateWatchGeneration else {
                return
            }

            if !event.intersection([.delete, .rename]).isEmpty {
                self.codexStateFileSource?.cancel()
                self.codexStateFileSource = nil
            }
            self.scheduleCodexSelectionRefresh()
        }
        // A source does not replay writes made before attachment. Read after
        // attaching so creation/replacement during a watcher gap is observed.
        if codexStateFileSource != nil {
            scheduleCodexSelectionRefresh()
        }
    }

    private func fileSystemSource(
        url: URL,
        eventMask: DispatchSource.FileSystemEvent,
        eventHandler: @escaping @MainActor (DispatchSource.FileSystemEvent) -> Void
    ) -> DispatchSourceFileSystemObject? {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            return nil
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: eventMask,
            queue: .main
        )
        source.setEventHandler {
            let event = source.data
            Task { @MainActor in
                eventHandler(event)
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        return source
    }

    private func startSessionIndexFileWatcherIfAvailable() {
        guard FileManager.default.fileExists(atPath: sessionIndexURL.path) else {
            sessionIndexFileSource?.cancel()
            sessionIndexFileSource = nil
            return
        }

        sessionIndexFileSource?.cancel()
        sessionIndexFileSource = fileSystemSource(
            url: sessionIndexURL,
            eventMask: [.write, .extend, .attrib, .delete, .rename]
        ) { [weak self] event in
            guard let self else {
                return
            }

            if !event.intersection([.delete, .rename]).isEmpty {
                self.sessionIndexFileSource?.cancel()
                self.sessionIndexFileSource = nil
            }
            self.taskSummariesDirty = true
            self.cachedThreadIndexSignature = nil
            self.scheduleRolloutActivityScan(delay: .milliseconds(100))
        }
    }

    private func schedulePetEventLogProcessing() {
        petEventDebounceTask?.cancel()
        petEventDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(75))
            guard !Task.isCancelled else {
                return
            }
            await self?.processPetEventLogChange()
        }
    }

    private func scheduleCodexSelectionRefresh() {
        guard preferences.followCodexPet else {
            return
        }

        codexStateDebounceTask?.cancel()
        let stateURL = codexStateURL
        codexStateDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else {
                return
            }

            let selectedPetID = await Task.detached(priority: .utility) {
                guard let data = try? Data(contentsOf: stateURL) else {
                    return nil as String?
                }
                return try? CodexGlobalState.selectedPetID(from: data)
            }.value

            guard !Task.isCancelled else {
                return
            }
            self?.applyCodexSelection(selectedPetID)
        }
    }

    private func processPetEventLogChange() async {
        if petEventLogWasReplaced {
            petEventLogWasReplaced = false
            reloadPetEventLogInBackground()
            return
        }
        guard petEventReloadTask == nil else {
            return
        }

        let previousOffset = petEventOffset
        let eventURL = petEventsURL
        let read = await Task.detached(priority: .utility) {
            var nextOffset = previousOffset
            do {
                let events = try CodexPetEventLog.readEvents(from: eventURL, startingAt: &nextOffset)
                return PetEventIncrementalRead(
                    events: events,
                    nextOffset: nextOffset,
                    wasReset: nextOffset < previousOffset,
                    didFail: false
                )
            } catch {
                return PetEventIncrementalRead(
                    events: [],
                    nextOffset: previousOffset,
                    wasReset: false,
                    didFail: true
                )
            }
        }.value
        guard !Task.isCancelled else {
            return
        }
        if read.didFail {
            // Re-arm through the maintenance cadence. This makes a lone final
            // event recover after a transient read error even when no later
            // write arrives to wake the existing file descriptor again. Treat
            // the path as replaced as well: the failing descriptor may have
            // belonged to the pre-rotation file, and resuming its byte offset
            // against a larger replacement would otherwise skip the new head.
            petEventFileSource?.cancel()
            petEventFileSource = nil
            petEventOffset = 0
            petEventLogWasReplaced = true
            return
        }
        if read.wasReset {
            reloadPetEventLogInBackground()
            return
        }

        petEventOffset = read.nextOffset
        petEventLogWasReplaced = false
        applyNewPetEvents(read.events)
    }

    private func applyNewPetEvents(_ newEvents: [CodexPetEvent]) {
        guard !newEvents.isEmpty else {
            return
        }

        let now = Date()
        let completed = completionTracker.consumeHookEvents(newEvents, now: now)
        let priorEvents = cachedPetEvents ?? []
        clearCompletionForFreshWork(newEvents, priorEvents: priorEvents, now: now)
        cachedPetEvents = compactPetEvents(priorEvents + newEvents, now: now)
        taskSummariesDirty = true
        if newEvents.contains(where: { ["stopped", "tool_failed", "permission_requested"].contains($0.kind) }) {
            refreshTaskSummariesInBackground(delay: .milliseconds(300))
        }
        let visibleStateChanged = applyActivitySnapshot(
            currentActivitySnapshot(now: now)
        )

        if completed { showCompletion() }
        if approvalRequestedForNextFrame || (reduceMotion && visibleStateChanged) {
            renderCurrentFrame()
        }
        updateTimerCadenceIfNeeded()
    }

    private func refreshHookActivityForExpiryIfNeeded(now: Date) {
        guard now.timeIntervalSince(lastHookSnapshotRefreshDate) >= RuntimeCadence.hookSnapshotRefreshInterval else {
            return
        }

        if petEventFileSource == nil {
            startPetEventFileWatcherIfAvailable()
            if petEventFileSource != nil {
                schedulePetEventLogProcessing()
            }
        }
        if codexStateFileSource == nil {
            startCodexStateFileWatcherIfAvailable()
        }
        updateHookActivitySnapshot(now: now)
    }

    private func refreshRolloutActivityIfNeeded(now: Date) {
        if sessionIndexFileSource == nil {
            startSessionIndexFileWatcherIfAvailable()
        }

        let interval = verifiedRunningCodexScopes.isEmpty
            ? RuntimeCadence.idleRolloutScanInterval
            : RuntimeCadence.activeRolloutScanInterval
        guard now.timeIntervalSince(lastRolloutActivityScanDate) >= interval else {
            return
        }
        scheduleRolloutActivityScan()
    }

    private func scheduleRolloutActivityScan(delay: Duration = .zero) {
        guard rolloutActivityScanTask == nil else {
            return
        }

        let sessionsRootURL = sessionsRootURL
        rolloutActivityScanTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else {
                return
            }

            let scanDate = Date()
            guard let self else {
                return
            }
            let hookCodexScopes = CodexPetEventLog.snapshot(
                events: self.cachedPetEvents ?? [],
                now: scanDate
            ).activeScopes.filter { $0.provider == .codex }
            let retainedCompletionThreadIDs = Set(
                hookCodexScopes.compactMap(\.sessionID) + hookCodexScopes.compactMap(\.parentSessionID)
            )
            let scan = await Task.detached(priority: .utility) {
                CodexRunningThreadScanner.activityScan(
                    in: sessionsRootURL,
                    now: scanDate,
                    staleAfter: RuntimeCadence.rolloutActivityStaleWindow,
                    retainedCompletionThreadIDs: retainedCompletionThreadIDs,
                    limit: RuntimeCadence.maximumRolloutScanThreadCount
                )
            }.value

            guard !Task.isCancelled else {
                return
            }
            self.rolloutActivityScanTask = nil
            self.lastRolloutActivityScanDate = scanDate

            let completed = self.completionTracker.consumeScan(scan, now: Date())
            let didChange = scan.runningScopes != self.verifiedRunningCodexScopes
                || scan.completedScopes != self.verifiedCompletedCodexScopes
            self.verifiedRunningCodexScopes = scan.runningScopes
            self.verifiedCompletedCodexScopes = scan.completedScopes
            guard didChange || completed else {
                return
            }

            let now = Date()
            self.taskSummariesDirty = true
            _ = self.applyActivitySnapshot(self.currentActivitySnapshot(now: now))
            if completed { self.showCompletion() }
            self.refreshTaskSummariesInBackground(delay: .milliseconds(100))
            if self.reduceMotion {
                self.renderCurrentFrame()
            }
            self.updateTimerCadenceIfNeeded()
        }
    }

    private func updateHookActivitySnapshot(now: Date) {
        lastHookSnapshotRefreshDate = now
        if cachedPetEvents == nil {
            reloadPetEventLogInBackground(now: now)
            return
        }

        _ = applyActivitySnapshot(
            currentActivitySnapshot(now: now)
        )
    }

    private func currentActivitySnapshot(now: Date) -> CodexPetActivitySnapshot {
        let events = cachedPetEvents ?? []
        let hookSnapshot = CodexPetEventLog.snapshot(events: events, now: now)
        return CodexPetActivityReconciler.merging(
            snapshot: hookSnapshot,
            runningCodexScopes: CodexRolloutHookPrecedence.filter(scopes: verifiedRunningCodexScopes, events: events),
            completedCodexScopes: CodexRolloutHookPrecedence.filter(scopes: verifiedCompletedCodexScopes, events: events)
        )
    }

    private func reloadPetEventLogInBackground(now: Date = Date()) {
        guard petEventReloadTask == nil else {
            return
        }

        lastHookSnapshotRefreshDate = now
        petEventDebounceTask?.cancel()
        let eventURL = petEventsURL
        petEventReloadTask = Task { [weak self] in
            let retainedLog = await Task.detached(priority: .utility) {
                try? CodexPetEventLog.retainedEvents(from: eventURL)
            }.value
            guard !Task.isCancelled, let self else {
                return
            }

            self.petEventReloadTask = nil
            guard let retainedLog else {
                // Keep the last good snapshot through a transient rotation or
                // read failure. Dropping the file source makes the maintenance
                // cadence both re-arm the watcher and retry the unread bytes.
                self.petEventFileSource?.cancel()
                self.petEventFileSource = nil
                self.petEventLogWasReplaced = true
                return
            }
            let refreshDate = Date()
            self.petEventOffset = retainedLog.activeReadOffset
            let completed = self.completionTracker.consumeHookEvents(retainedLog.events, now: refreshDate)
            self.clearCompletionForFreshWork(retainedLog.events, priorEvents: self.cachedPetEvents ?? [], now: refreshDate)
            self.cachedPetEvents = self.compactPetEvents(retainedLog.events, now: refreshDate)
            self.taskSummariesDirty = true
            _ = self.applyActivitySnapshot(
                self.currentActivitySnapshot(now: refreshDate)
            )
            if completed { self.showCompletion() }
            self.refreshTaskSummariesInBackground(delay: .milliseconds(100))
            self.startPetEventFileWatcherIfAvailable()
            self.schedulePetEventLogProcessing()
        }
    }

    @discardableResult
    private func applyActivitySnapshot(_ snapshot: CodexPetActivitySnapshot) -> Bool {
        let previousActivity = currentActivity
        let previousThreadCount = runningThreadCount
        let previousSessionIDs = activeSessionIDs
        let previousScopes = activeScopes

        if preferences.manualAnimationState == nil {
            currentActivity = snapshot.activity ?? .idle
        }
        let workStarted = snapshot.activeScopes.contains { scope in
            scope.activity == .running && !previousScopes.contains {
                $0.provider == scope.provider && $0.scopedIdentity == scope.scopedIdentity && $0.activity == .running
            }
        }
        if workStarted { completionVisibleUntil = nil }
        activeScopes = snapshot.activeScopes
        runningThreadCount = activeScopes.count
        activeSessionIDs = snapshot.activeSessionIDs
        // Cards and flags consume the same authoritative snapshot. Keep raw
        // summaries separately so a prior presentation cannot become evidence.
        cachedTaskSummaries = PetTaskSummaryBuilder.reconciling(
            tasks: cachedTaskSourceSummaries,
            snapshot: snapshot,
            completedCodexScopes: CodexRolloutHookPrecedence.filter(
                scopes: verifiedCompletedCodexScopes,
                events: cachedPetEvents ?? []
            )
        )
        let attentionPresentationChanged = synchronizeAttentionPresentation()

        let didChange = previousActivity != currentActivity
            || previousThreadCount != runningThreadCount
            || previousSessionIDs != activeSessionIDs
            || previousScopes != activeScopes
            || attentionPresentationChanged
        if didChange {
            updateStatusDescription()
            updateCursorGazeMonitoring()
            hoverPanelController.contentDidChange()
            if previousScopes != activeScopes {
                taskSummariesDirty = true
                refreshTaskSummariesInBackground(delay: .milliseconds(300))
            }
            // Present sleep/wake immediately before switching to the slower idle timer.
            renderCurrentFrame(deltaTime: 0)
            updateTimerCadenceIfNeeded()
        }
        return didChange
    }

    @discardableResult
    private func synchronizeAttentionPresentation() -> Bool {
        let previousScope = attentionPresentations.activeScope
        attentionPresentations.synchronize(scopes: activeScopes)
        let activeScope = attentionPresentations.activeScope
        guard activeScope != previousScope else {
            return false
        }

        if activeScope == nil {
            approvalRequestedForNextFrame = false
            attentionPresentationWasActive = false
            attentionRepeatCooldownRemaining = 0
            reducedMotionAttentionRemaining = 0
            runtime?.cancelApprovalPulse()
        } else {
            attentionRepeatCooldownRemaining = attentionPresentations.activePresentationIsRepeat
                ? RuntimeCadence.attentionRepeatCooldown
                : 0
            approvalRequestedForNextFrame = attentionRepeatCooldownRemaining == 0
            reducedMotionAttentionRemaining = RuntimeCadence.attentionPresentationDuration
        }
        updateCursorGazeMonitoring()
        return true
    }

    private func compactPetEvents(_ events: [CodexPetEvent], now: Date) -> [CodexPetEvent] {
        CodexPetEventLog.compactedEvents(
            events,
            now: now,
            retentionWindow: RuntimeCadence.hookReviewWindow,
            maximumCount: RuntimeCadence.maximumCachedPetEvents
        )
    }

    private func refreshTaskSummariesInBackground(delay: Duration = .zero) {
        guard taskSummaryRefreshTask == nil else {
            return
        }
        taskSummaryRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else {
                return
            }

            self.taskSummariesDirty = false
            let sessionIndexURL = self.sessionIndexURL
            let sessionsRootURL = self.sessionsRootURL
            let providerEvents = self.cachedPetEvents ?? []
            let summaries = await Task.detached(priority: .utility) {
                CodexTaskSummaryReader.read(
                    sessionIndexURL: sessionIndexURL,
                    sessionsRootURL: sessionsRootURL,
                    providerEvents: providerEvents
                )
            }.value

            guard !Task.isCancelled else {
                return
            }
            self.cachedTaskSourceSummaries = summaries
            _ = self.applyActivitySnapshot(self.currentActivitySnapshot(now: Date()))
            self.taskSummaryRefreshTask = nil
            self.hoverPanelController.contentDidChange()
            // A hook or index update while the read was in flight needs another
            // read; a completion must not clear that newer invalidation.
            if self.taskSummariesDirty {
                self.refreshTaskSummariesInBackground(delay: .milliseconds(100))
            }
        }
    }

    private func hoverPanelContent() -> PetHoverPanelContent {
        if taskSummariesDirty {
            refreshTaskSummariesInBackground()
        }
        let groups = PetTaskSummaryGrouping.groups(tasks: cachedTaskSummaries)
        return PetHoverPanelContent(
            petName: selectedPet?.displayName ?? "Codex Pet",
            statusText: taskStatusText,
            projects: PetTaskPresentationAdapter.taskGroups(groups)
        )
    }

    private var taskStatusText: String {
        if isShowingCompletion { return runningThreadCount == 0 ? "All done" : "Task finished" }
        if runningThreadCount == 1 {
            return "1 active task"
        }
        if runningThreadCount > 1 {
            return "\(runningThreadCount) active tasks"
        }

        switch currentActivity {
        case .idle:
            return "Up to date"
        case .running:
            return "Working"
        case .reviewing:
            return "Waiting for review"
        case .listening:
            return "Listening"
        case .failed:
            return "Needs attention"
        }
    }

    private func openPresentedTask(_ task: PetTaskPresentation) {
        if let deepLinkURL = task.deepLinkURL {
            NSWorkspace.shared.open(deepLinkURL)
            return
        }

        switch task.provider {
        case .cursor:
            guard let projectURL = task.projectURL else {
                NSSound.beep()
                return
            }
            openProjectInCursor(projectURL)
        case .claude:
            guard let projectURL = task.projectURL else {
                NSSound.beep()
                return
            }
            let resumableSessionID = task.navigationSourceID ?? task.sourceID
            if let deepLink = claudeCodeDeepLink(projectURL: projectURL, sourceID: resumableSessionID) {
                NSWorkspace.shared.open(deepLink)
            } else {
                NSWorkspace.shared.open(projectURL)
            }
        case .codex, .other:
            guard let projectURL = task.projectURL else {
                NSSound.beep()
                return
            }
            NSWorkspace.shared.open(projectURL)
        }
    }

    private func openProjectInCursor(_ projectURL: URL) {
        let cursorBundleID = "com.todesktop.230313mzl4w4u92"
        guard let cursorURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: cursorBundleID) else {
            NSWorkspace.shared.open(projectURL)
            return
        }

        NSWorkspace.shared.open(
            [projectURL],
            withApplicationAt: cursorURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    private func claudeCodeDeepLink(projectURL: URL, sourceID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "claude-cli"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "cwd", value: projectURL.path),
            URLQueryItem(name: "q", value: "/resume \(sourceID)"),
        ]
        guard
            let url = components.url,
            NSWorkspace.shared.urlForApplication(toOpen: url) != nil
        else {
            return nil
        }
        return url
    }

    private func setState(_ state: PetAnimationState) {
        if currentState != state {
            currentState = state
            manualFrameClock.reset()
        }
    }

    private func renderCurrentFrame(deltaTime: Double? = nil) {
        let deltaTime = deltaTime ?? frameDeltaTime()
        let renderState: RenderState
        if preferences.manualAnimationState != nil {
            renderState = manualRenderState(deltaTime: deltaTime)
        } else {
            renderState = automaticRenderState(deltaTime: deltaTime)
        }
        updateStatusDescription(
            animationState: renderState.animationState,
            attentionScope: renderState.attentionScope
        )
        let isDarkAppearance = ProviderBrandImages.isDark(
            statusItem.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        )

        guard let frames = spriteSheet?.frames(for: renderState.animationState), !frames.isEmpty else {
            let displayLength = providerAwareStatusLength(renderState.length)
            applyStatusLength(displayLength)
            statusItem.button?.image = activeScopes.isEmpty && renderState.attentionScope == nil && !isShowingCompletion
                ? fallbackPetImage
                : scaledImage(
                    fallbackPetImage,
                    length: displayLength,
                    playfieldLength: preferences.petSize.menuBarLength,
                    positionX: renderState.positionX,
                    scale: renderState.attentionScope == nil ? 0.82 : renderState.scale,
                    activeScopes: activeScopes,
                    attentionScope: renderState.attentionScope,
                    threadDotPhase: threadDotPhase,
                    isDarkAppearance: isDarkAppearance,
                    isSleeping: renderState.isSleeping,
                    showsCompletion: isShowingCompletion
                )
            isDisplayingFallback = true
            approvalRequestedForNextFrame = false
            return
        }
        isDisplayingFallback = false

        let directionalHeadingIndex = shouldTrackCursorGaze
            && renderState.animationState == .idle
            ? cursorGazeHeadingIndex
            : nil
        let directionalImage = directionalHeadingIndex.flatMap {
            spriteSheet?.directionalFrame(headingIndex: $0)
        }
        let frameIndex = directionalImage == nil ? renderState.frameIndex % frames.count : 0
        let displayLength = providerAwareStatusLength(renderState.length)
        let displayPositionX = renderState.positionX
        let renderKey = RenderKey(
            petID: selectedPet?.id,
            animationState: renderState.animationState,
            frameIndex: frameIndex,
            directionalHeadingIndex: directionalHeadingIndex,
            length: displayLength,
            positionX: displayPositionX,
            scale: renderState.scale,
            activeScopes: activeScopes,
            attentionScope: renderState.attentionScope,
            isDarkAppearance: isDarkAppearance,
            threadDotPhase: runningThreadCount > 0 ? threadDotPhase : 0,
            isSleeping: renderState.isSleeping,
            showsCompletion: isShowingCompletion
        )
        guard renderKey != lastRenderKey else {
            approvalRequestedForNextFrame = false
            return
        }

        let image: NSImage
        if let staticImageKey = staticImageKey(for: renderKey) {
            if let cachedImage = staticImageCache[staticImageKey] {
                image = cachedImage
            } else {
                image = scaledImage(
                    directionalImage ?? frames[frameIndex],
                    length: displayLength,
                    playfieldLength: preferences.petSize.menuBarLength,
                    positionX: displayPositionX,
                    scale: renderState.scale,
                    activeScopes: activeScopes,
                    attentionScope: renderState.attentionScope,
                    threadDotPhase: threadDotPhase,
                    isDarkAppearance: isDarkAppearance,
                    isSleeping: renderState.isSleeping,
                    showsCompletion: isShowingCompletion
                )
                if staticImageCache.count >= RuntimeCadence.maximumStaticImageCacheEntries {
                    staticImageCache.removeAll(keepingCapacity: true)
                }
                staticImageCache[staticImageKey] = image
            }
        } else {
            image = scaledImage(
                directionalImage ?? frames[frameIndex],
                length: displayLength,
                playfieldLength: preferences.petSize.menuBarLength,
                positionX: displayPositionX,
                scale: renderState.scale,
                activeScopes: activeScopes,
                attentionScope: renderState.attentionScope,
                threadDotPhase: threadDotPhase,
                isDarkAppearance: isDarkAppearance,
                isSleeping: renderState.isSleeping,
                showsCompletion: isShowingCompletion
            )
        }
        applyStatusLength(displayLength)
        statusItem.button?.image = image
        lastRenderKey = renderKey
        approvalRequestedForNextFrame = false
    }

    private func frameDeltaTime(now: Date = Date()) -> Double {
        defer { lastFrameDate = now }

        guard let lastFrameDate else {
            return currentTimerInterval ?? RuntimeCadence.activeFrameInterval
        }

        return min(0.5, max(0, now.timeIntervalSince(lastFrameDate)))
    }

    private func updateThreadDots(deltaTime: Double) {
        if runningThreadCount > 0, !reduceMotion {
            threadDotPhase = (threadDotPhase + max(0, deltaTime) * 4.6)
                .truncatingRemainder(dividingBy: 2 * .pi)
        } else if reduceMotion {
            threadDotPhase = 0
        }
    }

    private func providerAwareStatusLength(_ contentLength: Double) -> Double {
        PetMenuBarPresentation.contentWidth(
            petWidth: contentLength,
            providerCount: PetMenuBarPresentation.providerIndicators(for: activeScopes).count
        )
            + (isShowingCompletion ? PetMenuBarPresentation.completionAccessoryWidth : 0)
    }

    private var isShowingCompletion: Bool {
        completionVisibleUntil != nil && preferences.manualAnimationState == nil
    }

    private var motionActivity: CodexActivity {
        activeScopes.contains { $0.activity == .running } ? .running : currentActivity
    }

    private func clearCompletionForFreshWork(_ events: [CodexPetEvent], priorEvents: [CodexPetEvent], now: Date) {
        guard completionVisibleUntil != nil else { return }
        let freshPrompt = events.contains { event in
            guard event.kind == "prompt_submitted", event.parentSessionID == nil,
                  event.timestamp >= now.timeIntervalSince1970 - 5,
                  event.timestamp <= now.timeIntervalSince1970 + 5 else { return false }
            let latestPriorTimestamp = priorEvents.lazy.filter {
                $0.provider == event.provider && $0.sessionID == event.sessionID
            }.map(\.timestamp).max() ?? -Double.infinity
            return event.timestamp > latestPriorTimestamp
        }
        if freshPrompt {
            completionVisibleUntil = nil
            hoverPanelController.contentDidChange()
            updateCursorGazeMonitoring()
        }
    }

    private func showCompletion() {
        guard preferences.manualAnimationState == nil else { return }
        completionVisibleUntil = Date().addingTimeInterval(5)
        hoverPanelController.contentDidChange()
        updateCursorGazeMonitoring()
        renderCurrentFrame(deltaTime: 0)
        updateTimerCadenceIfNeeded()
    }

    private func expireCompletion(now: Date) {
        guard let deadline = completionVisibleUntil, now >= deadline else { return }
        completionVisibleUntil = nil
        hoverPanelController.contentDidChange()
        updateCursorGazeMonitoring()
    }

    private var isSleeping: Bool {
        PetMenuBarPresentation.shouldSleep(
            activity: currentActivity,
            activeTaskCount: runningThreadCount,
            manualAnimationState: preferences.manualAnimationState,
            hasReaction: reactionState != nil || reactionRemaining > 0 || isShowingCompletion,
            hasAttention: approvalRequestedForNextFrame
                || attentionPresentations.activeScope != nil
                || attentionPresentationWasActive
        )
    }

    private func manualRenderState(deltaTime: Double) -> RenderState {
        let state = preferences.manualAnimationState ?? currentState
        setState(state)
        let frames = spriteSheet?.frames(for: state) ?? []
        if reduceMotion {
            manualFrameClock.reset()
        } else {
            manualFrameClock.advanceAfterDisplay(
                deltaTime: deltaTime,
                metadata: PetAtlasMetadata.playbackRow(for: state),
                frameCount: frames.count
            )
        }
        let metrics = renderMetrics(length: preferences.petSize.menuBarLength)
        let petWidth = PetMenuBarPresentation.sleepingWidth(spriteWidth: metrics.spriteWidth)
        return RenderState(
            animationState: state,
            frameIndex: manualFrameClock.frameIndex,
            positionX: max(0, (petWidth - metrics.spriteWidth) / 2),
            scale: 1,
            length: petWidth,
            attentionScope: nil
        )
    }

    private func automaticRenderState(deltaTime: Double) -> RenderState {
        let metrics = renderMetrics(length: preferences.petSize.menuBarLength)
        let petWidth = PetMenuBarPresentation.petWidth(
            spriteWidth: metrics.spriteWidth,
            preferredWidth: preferences.petSize.menuBarLength,
            isRunning: motionActivity == .running
        )
        let completionReaction: PetAnimationState? = isShowingCompletion && activeScopes.isEmpty ? .jumping : nil
        if isSleeping {
            let length = PetMenuBarPresentation.sleepingWidth(spriteWidth: metrics.spriteWidth)
            return RenderState(
                animationState: .idle,
                frameIndex: PetMenuBarPresentation.sleepingFrameIndex(
                    petID: selectedPet?.id,
                    frameCount: spriteSheet?.frames(for: .idle).count ?? 0
                ),
                positionX: (length - metrics.spriteWidth) / 2,
                scale: 1,
                length: length,
                attentionScope: nil,
                isSleeping: true
            )
        }
        advanceAttentionRepeatCooldown(deltaTime: deltaTime)
        if reduceMotion {
            let presentedScope = attentionRepeatCooldownRemaining == 0
                ? attentionPresentations.activeScope
                : nil
            let animationState = presentedScope == nil
                ? (reactionState ?? completionReaction ?? motionActivity.animationState)
                : .waving
            let length = presentedScope == nil
                ? petWidth
                : petWidth + RuntimeCadence.heldFlagSpace
            let state = RenderState(
                animationState: animationState,
                frameIndex: 0,
                positionX: max(0, (petWidth - metrics.spriteWidth) / 2),
                scale: 1,
                length: length,
                attentionScope: presentedScope
            )
            advanceReducedMotionAttention(deltaTime: deltaTime)
            return state
        }

        let layout = PetRuntimeLayout(playfieldWidth: petWidth, spriteWidth: metrics.spriteWidth)
        var runtime = runtime ?? PetRuntime(
            playfieldWidth: layout.playfieldWidth,
            spriteWidth: layout.spriteWidth,
            motionSpeed: 18
        )
        if runtimeLayout != layout {
            runtime.resetLayout(playfieldWidth: layout.playfieldWidth, spriteWidth: layout.spriteWidth, motionSpeed: 18)
            runtimeLayout = layout
            attentionPresentationWasActive = false
        }

        let presentedScope = attentionPresentations.activeScope
        let shouldStartAttention = approvalRequestedForNextFrame
            || (
                !attentionPresentationWasActive
                    && attentionRepeatCooldownRemaining == 0
                    && presentedScope != nil
            )
        let frame = runtime.tick(
            activity: motionActivity,
            reactionState: reactionState ?? completionReaction,
            approvalRequested: shouldStartAttention,
            deltaTime: deltaTime
        )
        self.runtime = runtime

        if attentionPresentationWasActive, !frame.isApprovalPulseActive {
            attentionPresentations.presentationDidFinish()
            attentionRepeatCooldownRemaining = attentionPresentations.activePresentationIsRepeat
                ? RuntimeCadence.attentionRepeatCooldown
                : 0
        }
        attentionPresentationWasActive = frame.isApprovalPulseActive

        let attentionScope = frame.isApprovalPresentationActive ? presentedScope : nil
        let length = attentionScope == nil
            ? petWidth
            : petWidth + RuntimeCadence.heldFlagSpace
        return RenderState(
            animationState: frame.animationState,
            frameIndex: frame.frameIndex,
            positionX: frame.positionX,
            // Keep the whole pet at its normal menu-bar height while waving.
            scale: 1,
            length: length,
            attentionScope: attentionScope
        )
    }

    private func advanceReducedMotionAttention(deltaTime: Double) {
        guard
            attentionRepeatCooldownRemaining == 0,
            attentionPresentations.activeScope != nil
        else {
            reducedMotionAttentionRemaining = 0
            return
        }

        if reducedMotionAttentionRemaining <= 0 {
            reducedMotionAttentionRemaining = RuntimeCadence.attentionPresentationDuration
        }
        reducedMotionAttentionRemaining = max(
            0,
            reducedMotionAttentionRemaining - max(0, deltaTime)
        )
        guard reducedMotionAttentionRemaining == 0 else {
            return
        }

        attentionPresentations.presentationDidFinish()
        if attentionPresentations.activeScope != nil {
            attentionRepeatCooldownRemaining = attentionPresentations.activePresentationIsRepeat
                ? RuntimeCadence.attentionRepeatCooldown
                : 0
            reducedMotionAttentionRemaining = RuntimeCadence.attentionPresentationDuration
        }
    }

    private func advanceAttentionRepeatCooldown(deltaTime: Double) {
        guard attentionRepeatCooldownRemaining > 0 else {
            return
        }
        attentionRepeatCooldownRemaining = max(
            0,
            attentionRepeatCooldownRemaining - max(0, deltaTime)
        )
    }

    private func refreshPets(playReaction: Bool) {
        let loadResult = petLibrary.loadPetsWithDiagnostics()
        pets = loadResult.pets
        petLoadIssues = loadResult.issues
        let codexSelectedPetID = readCodexSelectedPetID()
        lastCodexSelectedPetID = codexSelectedPetID
        selectedPet = PetSelection.resolve(
            pets: pets,
            preferences: preferences,
            codexSelectedPetID: codexSelectedPetID
        )
        loadSelectedPet()
        hoverPanelController.contentDidChange()
        if playReaction {
            triggerReaction(.waving)
            renderCurrentFrame()
        }
    }

    private func applyCodexSelection(_ selectedPetID: String?) {
        guard preferences.followCodexPet else {
            return
        }

        guard selectedPetID != lastCodexSelectedPetID else {
            return
        }
        lastCodexSelectedPetID = selectedPetID
        let resolvedPet = PetSelection.resolve(
            pets: pets,
            preferences: preferences,
            codexSelectedPetID: selectedPetID
        )
        guard resolvedPet?.id != selectedPet?.id else {
            return
        }

        selectedPet = resolvedPet
        loadSelectedPet()
        hoverPanelController.contentDidChange()
        triggerReaction(.waving)
        renderCurrentFrame()
    }

    private func readCodexSelectedPetID() -> String? {
        guard let data = try? Data(contentsOf: codexStateURL) else {
            return nil
        }
        return try? CodexGlobalState.selectedPetID(from: data)
    }

    private func loadSelectedPet() {
        resetAnimationRuntime()
        guard let selectedPet else {
            spriteSheet = nil
            selectedPetLoadError = nil
            updateCursorGazeMonitoring()
            return
        }

        do {
            spriteSheet = try PetSpriteSheet(package: selectedPet)
            selectedPetLoadError = nil
        } catch {
            spriteSheet = nil
            selectedPetLoadError = error.localizedDescription
        }
        updateCursorGazeMonitoring()
    }

    private func startAccessibilityObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @objc private func accessibilityDisplayOptionsDidChange() {
        let shouldReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard shouldReduceMotion != reduceMotion else {
            return
        }

        reduceMotion = shouldReduceMotion
        resetAnimationRuntime()
        updateCursorGazeMonitoring()
        renderCurrentFrame()
        updateTimerCadenceIfNeeded()
    }

    private func makeMenu() -> NSMenu {
        if taskSummariesDirty {
            refreshTaskSummariesInBackground()
        }
        let menu = NSMenu()
        menu.minimumWidth = 260
        menu.autoenablesItems = false

        let title = selectedPet?.displayName ?? "No Codex Pet"
        let titleItem = NSMenuItem(title: "\(title) · \(taskStatusText)", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        titleItem.image = statusItem.button?.image.map {
            ProviderBrandImages.fittedImage($0, dimension: 18)
        } ?? menuSymbol("pawprint.fill", description: title)
        menu.addItem(titleItem)

        if let selectedPetLoadError {
            let item = NSMenuItem(
                title: "Couldn’t load \(title): \(selectedPetLoadError)",
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
            item.image = menuSymbol("exclamationmark.triangle", description: "Pet load error")
            menu.addItem(item)
        }

        if !petLoadIssues.isEmpty {
            let issuesItem = NSMenuItem(
                title: petLoadIssues.count == 1 ? "1 invalid pet ignored" : "\(petLoadIssues.count) invalid pets ignored",
                action: nil,
                keyEquivalent: ""
            )
            issuesItem.image = menuSymbol("exclamationmark.triangle", description: "Invalid pets")
            let issuesMenu = NSMenu()
            for issue in petLoadIssues {
                let item = NSMenuItem(
                    title: "\(issue.packageName): \(issue.message)",
                    action: nil,
                    keyEquivalent: ""
                )
                item.isEnabled = false
                item.image = menuSymbol("xmark.circle", description: "Invalid pet")
                issuesMenu.addItem(item)
            }
            menu.setSubmenu(issuesMenu, for: issuesItem)
            menu.addItem(issuesItem)
        }
        menu.addItem(.separator())

        menu.addItem(taskHierarchyMenuItem())
        menu.addItem(petsMenuItem())
        menu.addItem(appearanceMenuItem())
        menu.addItem(integrationsMenuItem())
        menu.addItem(utilitiesMenuItem())

        menu.addItem(.separator())
        loginItemController.addMenuItems(to: menu)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = menuSymbol("power", description: "Quit")
        menu.addItem(quitItem)

        return menu
    }

    private func taskHierarchyMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Tasks", action: nil, keyEquivalent: "")
        item.image = menuSymbol("list.bullet.rectangle", description: "Tasks")
        let submenu = NSMenu(title: "Tasks")
        let groups = PetTaskPresentationAdapter.taskGroups(
            PetTaskSummaryGrouping.groups(tasks: cachedTaskSummaries)
        )

        if groups.isEmpty {
            let emptyItem = NSMenuItem(title: "No recent tasks", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            emptyItem.image = menuSymbol("checkmark.circle", description: "No recent tasks")
            submenu.addItem(emptyItem)
        } else {
            for group in groups {
                let projectItem = NSMenuItem(title: shortMenuTitle(group.name), action: nil, keyEquivalent: "")
                projectItem.image = menuSymbol("folder", description: group.name)
                let projectMenu = NSMenu(title: group.name)
                for task in group.tasks {
                    projectMenu.addItem(nativeTaskMenuItem(task))
                }
                submenu.setSubmenu(projectMenu, for: projectItem)
                submenu.addItem(projectItem)
            }
        }

        item.submenu = submenu
        return item
    }

    private func nativeTaskMenuItem(_ task: PetTaskPresentation) -> NSMenuItem {
        let item = NSMenuItem(
            title: shortMenuTitle(task.title),
            action: #selector(openPresentedTaskFromMenu(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = task
        item.image = ProviderBrandImages.menuImage(
            for: task.provider,
            appearance: statusItem.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        )
        item.toolTip = "\(task.summary) — \(task.state.displayName)"
        item.setAccessibilityLabel("\(task.title), \(task.provider.displayName), \(task.state.displayName)")
        item.setAccessibilityHelp(task.accessibilityOpenHint)
        return item
    }

    private func petsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Pets", action: nil, keyEquivalent: "")
        item.image = menuSymbol("pawprint", description: "Pets")
        let submenu = NSMenu(title: "Pets")
        if pets.isEmpty {
            let emptyItem = NSMenuItem(title: "No valid pets found", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
        } else {
            for pet in pets {
                let petItem = NSMenuItem(
                    title: shortMenuTitle(pet.displayName),
                    action: #selector(selectPet(_:)),
                    keyEquivalent: ""
                )
                petItem.target = self
                petItem.representedObject = pet.id
                petItem.state = pet.id == selectedPet?.id ? .on : .off
                petItem.image = menuSymbol("pawprint.fill", description: pet.displayName)
                submenu.addItem(petItem)
            }
        }
        item.submenu = submenu
        return item
    }

    private func appearanceMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        item.image = menuSymbol("paintbrush", description: "Appearance")
        let submenu = NSMenu(title: "Appearance")

        let followItem = NSMenuItem(
            title: "Follow Codex Pet",
            action: #selector(toggleFollowCodexPet),
            keyEquivalent: ""
        )
        followItem.target = self
        followItem.state = preferences.followCodexPet ? .on : .off
        followItem.image = menuSymbol("link", description: "Follow Codex Pet")
        submenu.addItem(followItem)
        submenu.addItem(.separator())

        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        sizeItem.image = menuSymbol("textformat.size", description: "Size")
        let sizeMenu = NSMenu(title: "Size")
        for size in PetSize.allCases {
            let option = NSMenuItem(
                title: size.rawValue.capitalized,
                action: #selector(selectSize(_:)),
                keyEquivalent: ""
            )
            option.target = self
            option.representedObject = size.rawValue
            option.state = size == preferences.petSize ? .on : .off
            option.image = menuSymbol("\(size.rawValue.prefix(1)).circle", description: option.title)
            sizeMenu.addItem(option)
        }
        sizeItem.submenu = sizeMenu
        submenu.addItem(sizeItem)

        let animationItem = NSMenuItem(title: "Animation", action: nil, keyEquivalent: "")
        animationItem.image = menuSymbol("play.circle", description: "Animation")
        let animationMenu = NSMenu(title: "Animation")
        let automaticItem = NSMenuItem(
            title: "Automatic",
            action: #selector(selectAutomaticState),
            keyEquivalent: ""
        )
        automaticItem.target = self
        automaticItem.state = preferences.manualAnimationState == nil ? .on : .off
        automaticItem.image = menuSymbol("sparkles", description: "Automatic")
        animationMenu.addItem(automaticItem)
        animationMenu.addItem(.separator())
        for state in PetAnimationState.allCases {
            let option = NSMenuItem(
                title: state.rawValue.capitalized,
                action: #selector(selectState(_:)),
                keyEquivalent: ""
            )
            option.target = self
            option.representedObject = state.rawValue
            option.state = state == preferences.manualAnimationState ? .on : .off
            option.image = menuSymbol(animationMenuSymbol(for: state), description: option.title)
            animationMenu.addItem(option)
        }
        animationItem.submenu = animationMenu
        submenu.addItem(animationItem)

        item.submenu = submenu
        return item
    }

    private func integrationsMenuItem() -> NSMenuItem {
        let healthByProvider = providerIntegrationHealth()
        let item = NSMenuItem(
            title: integrationSummaryTitle(healthByProvider),
            action: nil,
            keyEquivalent: ""
        )
        item.image = menuSymbol("point.3.connected.trianglepath.dotted", description: "Integrations")
        item.toolTip = integrationSummaryToolTip(healthByProvider)
        let submenu = NSMenu(title: "Integrations")

        let allItem = integrationInstallMenuItem(
            title: "Install / Repair All",
            provider: "all",
            health: nil
        )
        allItem.toolTip = "Install or repair the local Codex, Claude Code, and Cursor hooks."
        submenu.addItem(allItem)
        submenu.addItem(.separator())
        for provider in PetProvider.allCases {
            submenu.addItem(
                integrationInstallMenuItem(
                    title: providerIntegrationDisplayName(provider),
                    provider: provider.rawValue,
                    health: healthByProvider[provider]
                )
            )
        }

        item.submenu = submenu
        return item
    }

    private func integrationInstallMenuItem(
        title: String,
        provider: String,
        health: ProviderIntegrationHealth?
    ) -> NSMenuItem {
        let displayedTitle: String
        if isInstallingHooks {
            displayedTitle = "\(title) · Installing…"
        } else if let health {
            displayedTitle = "\(title) · \(integrationHealthLabel(health.state))"
        } else {
            displayedTitle = title
        }
        let item = NSMenuItem(
            title: displayedTitle,
            action: #selector(installIntegration(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = provider
        item.isEnabled = !isInstallingHooks
        if let health {
            item.state = integrationMenuState(health.state)
            item.toolTip = integrationHealthToolTip(health)
            item.setAccessibilityLabel("\(title), \(integrationHealthLabel(health.state))")
            item.setAccessibilityHelp(integrationHealthToolTip(health))
        }
        let appearance = statusItem.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        switch provider {
        case "codex":
            item.image = ProviderBrandImages.menuImage(for: PetProvider.codex, appearance: appearance)
        case "claude":
            item.image = ProviderBrandImages.menuImage(for: PetProvider.claude, appearance: appearance)
        case "cursor":
            item.image = ProviderBrandImages.menuImage(for: PetProvider.cursor, appearance: appearance)
        default:
            item.image = menuSymbol("square.grid.2x2", description: "All integrations")
        }
        return item
    }

    private func providerIntegrationHealth() -> [PetProvider: ProviderIntegrationHealth] {
        let fileManager = FileManager.default
        let codexHome = petEventsURL.deletingLastPathComponent().resolvingSymlinksInPath()
        let installedHookURL = codexHome
            .appendingPathComponent("hooks", isDirectory: true)
            .appendingPathComponent("codex_pet_event.py")
        let installedHookData = try? Data(contentsOf: installedHookURL)
        let installedHookModificationTimestamp = (
            try? installedHookURL.resourceValues(forKeys: [.contentModificationDateKey])
        )?.contentModificationDate?.timeIntervalSince1970
        let currentHookData = currentHookScriptURL().flatMap { try? Data(contentsOf: $0) }
        let hookRuntimeAvailable = fileManager.isExecutableFile(atPath: "/usr/bin/python3")
        let events = cachedPetEvents ?? []

        return Dictionary(uniqueKeysWithValues: PetProvider.allCases.map { provider in
            let configURL = providerConfigURL(provider)
            let configModificationTimestamp = (
                try? configURL.resourceValues(forKeys: [.contentModificationDateKey])
            )?.contentModificationDate?.timeIntervalSince1970
            let adjacentMarkerURL = petEventsURL.deletingLastPathComponent()
                .appendingPathComponent(
                    "\(petEventsURL.lastPathComponent).\(provider.rawValue).error.json"
                )
            let fallbackMarkerName = "codex-pet-bar-hook-\(getuid())-\(provider.rawValue).error.json"
            let fallbackMarkerURLs = [
                fileManager.temporaryDirectory.appendingPathComponent(fallbackMarkerName),
                URL(fileURLWithPath: "/private/tmp", isDirectory: true)
                    .appendingPathComponent(fallbackMarkerName),
            ]
            let markerData = ([adjacentMarkerURL] + fallbackMarkerURLs).compactMap {
                try? Data(contentsOf: $0)
            }
            let input = ProviderIntegrationHealthInput(
                provider: provider,
                configData: try? Data(contentsOf: configURL),
                installedHookData: installedHookData,
                currentHookData: currentHookData,
                installedHookPath: installedHookURL.path,
                configModificationTimestamp: configModificationTimestamp,
                installedHookModificationTimestamp: installedHookModificationTimestamp,
                hookRuntimeAvailable: hookRuntimeAvailable,
                events: events,
                deliveryErrorMarkerData: markerData
            )
            return (provider, ProviderIntegrationHealthEvaluator.evaluate(input))
        })
    }

    private func providerConfigURL(_ provider: PetProvider) -> URL {
        switch provider {
        case .codex:
            petEventsURL.deletingLastPathComponent().appendingPathComponent("hooks.json")
        case .claude:
            providerConfigDirectory(environmentKey: "CLAUDE_CONFIG_DIR", defaultName: ".claude")
                .appendingPathComponent("settings.json")
        case .cursor:
            providerConfigDirectory(environmentKey: "CURSOR_CONFIG_DIR", defaultName: ".cursor")
                .appendingPathComponent("hooks.json")
        }
    }

    private func providerConfigDirectory(environmentKey: String, defaultName: String) -> URL {
        let fileManager = FileManager.default
        guard
            let configured = ProcessInfo.processInfo.environment[environmentKey]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !configured.isEmpty
        else {
            return fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(defaultName, isDirectory: true)
        }
        if configured == "~" {
            return fileManager.homeDirectoryForCurrentUser
        }
        if configured.hasPrefix("~/") {
            return fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(String(configured.dropFirst(2)), isDirectory: true)
                .standardizedFileURL
        }
        if configured.hasPrefix("/") {
            return URL(fileURLWithPath: configured, isDirectory: true).standardizedFileURL
        }
        return URL(
            fileURLWithPath: fileManager.currentDirectoryPath,
            isDirectory: true
        )
        .appendingPathComponent(configured, isDirectory: true)
        .standardizedFileURL
    }

    private func currentHookScriptURL() -> URL? {
        guard let installerURL = hookInstallerURL() else {
            return nil
        }
        let candidate = installerURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("hooks", isDirectory: true)
            .appendingPathComponent("codex_pet_event.py")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    private func providerIntegrationDisplayName(_ provider: PetProvider) -> String {
        switch provider {
        case .codex:
            "Codex"
        case .claude:
            "Claude Code"
        case .cursor:
            "Cursor"
        }
    }

    private func integrationHealthLabel(_ state: ProviderIntegrationHealthState) -> String {
        switch state {
        case .notInstalled:
            "Not installed"
        case .needsUpdate:
            "Update"
        case .deliveryError:
            "Delivery error"
        case .noSignal:
            "No signal"
        case .connected:
            "Connected"
        }
    }

    private func integrationMenuState(_ state: ProviderIntegrationHealthState) -> NSControl.StateValue {
        switch state {
        case .notInstalled:
            .off
        case .needsUpdate, .deliveryError, .noSignal:
            .mixed
        case .connected:
            .on
        }
    }

    private func integrationHealthToolTip(_ health: ProviderIntegrationHealth) -> String {
        switch health.state {
        case .notInstalled:
            "Local hooks aren’t installed. Click to install."
        case .needsUpdate:
            "Hooks are incomplete or use an older script. Click to update."
        case .deliveryError:
            if health.hookRuntimeAvailable {
                "The newest local hook delivery failed after the last activity received. Click to repair."
            } else {
                "The local Python hook runtime is unavailable, so activity can’t be delivered."
            }
        case .noSignal:
            "Hooks are current. Start a new local run to verify delivery; Codex may also require hook trust or restart."
        case .connected:
            "Hooks are current and have delivered local activity. Click to reinstall."
        }
    }

    private func integrationSummaryTitle(
        _ healthByProvider: [PetProvider: ProviderIntegrationHealth]
    ) -> String {
        let states = healthByProvider.values.map(\.state)
        if states.contains(.deliveryError) {
            return "Integrations · Error"
        }
        if states.contains(.needsUpdate) || states.contains(.notInstalled) {
            return "Integrations · Setup"
        }
        if states.allSatisfy({ $0 == .connected }) {
            return "Integrations · Connected"
        }
        return "Integrations · Verify"
    }

    private func integrationSummaryToolTip(
        _ healthByProvider: [PetProvider: ProviderIntegrationHealth]
    ) -> String {
        PetProvider.allCases.compactMap { provider in
            healthByProvider[provider].map {
                "\(providerIntegrationDisplayName(provider)): \(integrationHealthLabel($0.state))"
            }
        }
        .joined(separator: " · ")
    }

    private func utilitiesMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Utilities", action: nil, keyEquivalent: "")
        item.image = menuSymbol("wrench.and.screwdriver", description: "Utilities")
        let submenu = NSMenu(title: "Utilities")

        let refreshItem = NSMenuItem(
            title: "Refresh Pets",
            action: #selector(refreshPetsFromMenu),
            keyEquivalent: "r"
        )
        refreshItem.keyEquivalentModifierMask = [.command]
        refreshItem.target = self
        refreshItem.image = menuSymbol("arrow.clockwise", description: "Refresh Pets")
        submenu.addItem(refreshItem)

        let openPetsItem = NSMenuItem(
            title: "Open Pets Folder",
            action: #selector(openPetsFolder),
            keyEquivalent: ""
        )
        openPetsItem.target = self
        openPetsItem.image = menuSymbol("folder", description: "Open Pets Folder")
        submenu.addItem(openPetsItem)

        item.submenu = submenu
        return item
    }

    private func menuSymbol(_ name: String, description: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        image?.isTemplate = true
        return image
    }

    private func animationMenuSymbol(for state: PetAnimationState) -> String {
        switch state {
        case .idle:
            "pause.circle"
        case .runningRight:
            "arrow.right.circle"
        case .runningLeft:
            "arrow.left.circle"
        case .waving:
            "hand.wave"
        case .jumping:
            "arrow.up.circle"
        case .failed:
            "exclamationmark.triangle"
        case .waiting:
            "hand.raised"
        case .running:
            "arrow.triangle.2.circlepath"
        case .review:
            "checkmark.circle"
        }
    }

    private func shortMenuTitle(_ title: String) -> String {
        guard title.count > 30 else {
            return title
        }
        return String(title.prefix(27)) + "..."
    }

    private func addThreadItems(to menu: NSMenu) {
        let threads = recentThreadsForMenu()
        guard !threads.isEmpty else {
            return
        }

        let rows = CodexThreadMenuRows.build(threads: threads)
        let runningThreadIDs = activeSessionIDs
        let entries = CodexThreadMenuEntries.build(rows: rows, runningThreadIDs: runningThreadIDs)
        guard !entries.isEmpty else {
            return
        }

        for entry in entries {
            switch entry {
            case .sectionHeader(let title):
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            case .thread(let row):
                menu.addItem(threadMenuItem(for: row, isRunning: runningThreadIDs.contains(row.id)))
            case .more(let rows):
                let item = NSMenuItem(title: "More Threads", action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                for row in rows {
                    submenu.addItem(threadMenuItem(for: row, isRunning: runningThreadIDs.contains(row.id)))
                }
                menu.setSubmenu(submenu, for: item)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
    }

    private func recentThreadsForMenu() -> [CodexThreadSummary] {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: sessionIndexURL.path) else {
            cachedThreadIndexSignature = nil
            cachedRecentThreads = []
            return []
        }

        let signature = ThreadIndexSignature(
            fileSize: attributes[.size] as? UInt64 ?? 0,
            modificationDate: attributes[.modificationDate] as? Date
        )
        guard signature != cachedThreadIndexSignature else {
            return cachedRecentThreads
        }

        cachedThreadIndexSignature = signature
        cachedRecentThreads = CodexSessionIndexLog.readRecentThreads(from: sessionIndexURL, limit: 12)
        return cachedRecentThreads
    }

    private func threadMenuItem(for row: CodexThreadMenuRow, isRunning: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: row.title, action: #selector(openThread(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = row.deepLinkURL
        item.toolTip = isRunning ? "\(row.folderTitle) — Running" : row.folderTitle
        item.setAccessibilityLabel(isRunning ? "\(row.title), running" : row.title)
        item.image = threadBadgeImage(isRunning: isRunning)
        return item
    }

    private func threadBadgeImage(isRunning: Bool) -> NSImage? {
        if let cachedImage = threadBadgeImageCache[isRunning] {
            return cachedImage
        }

        guard let source = ProviderBrandImages.inAppImage(
            for: PetProvider.codex,
            isDark: ProviderBrandImages.isDark(
                statusItem.button?.effectiveAppearance ?? NSApp.effectiveAppearance
            )
        ) else {
            return nil
        }

        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        source.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .sourceOver,
            fraction: isRunning ? 1 : 0.72
        )
        image.unlockFocus()
        image.isTemplate = false
        threadBadgeImageCache[isRunning] = image
        return image
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
        applyStatusLength(size.menuBarLength)
        resetAnimationRuntime()
        refreshCursorGazeForCurrentPointer()
        renderCurrentFrame()
    }

    @objc private func selectAutomaticState() {
        preferences.manualAnimationState = nil
        updateHookActivitySnapshot(now: Date())
        resetAnimationRuntime()
        updateCursorGazeMonitoring()
        renderCurrentFrame()
        updateTimerCadenceIfNeeded()
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
        updateCursorGazeMonitoring()
        renderCurrentFrame()
        updateTimerCadenceIfNeeded()
    }

    @objc private func refreshPetsFromMenu() {
        refreshPets(playReaction: true)
    }

    @objc private func openPetsFolder() {
        NSWorkspace.shared.open(petLibrary.petsDirectory)
    }

    @objc private func openThread(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func openPresentedTaskFromMenu(_ sender: NSMenuItem) {
        guard let task = sender.representedObject as? PetTaskPresentation else {
            return
        }
        openPresentedTask(task)
    }

    @objc private func installIntegration(_ sender: NSMenuItem) {
        guard let provider = sender.representedObject as? String else {
            return
        }
        installHooks(provider: provider)
    }

    @objc private func installHooksGlobally() {
        installHooks(provider: "codex")
    }

    private func installHooks(provider: String) {
        guard !isInstallingHooks else {
            return
        }

        guard let installerURL = hookInstallerURL() else {
            showHookInstallResult(
                HookInstallResult(
                    exitCode: 1,
                    output: "",
                    error: "",
                    launchError: "Could not find install_hooks.py in the app bundle or source checkout."
                )
            )
            return
        }

        isInstallingHooks = true
        Task.detached(priority: .userInitiated) {
            let result = HookInstaller.run(installerURL: installerURL, provider: provider)
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }

                self.isInstallingHooks = false
                if result.succeeded {
                    self.triggerReaction(.waving)
                }
                self.showHookInstallResult(result)
            }
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func hookInstallerURL() -> URL? {
        let fileManager = FileManager.default
        let bundledURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("SharedSupport", isDirectory: true)
            .appendingPathComponent("script", isDirectory: true)
            .appendingPathComponent("install_hooks.py")
        if fileManager.fileExists(atPath: bundledURL.path) {
            return bundledURL
        }

        let workingDirectoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        let sourceURL = workingDirectoryURL
            .appendingPathComponent("script", isDirectory: true)
            .appendingPathComponent("install_hooks.py")
        if fileManager.fileExists(atPath: sourceURL.path) {
            return sourceURL
        }

        guard let executableURL = Bundle.main.executableURL else {
            return nil
        }

        var directory = executableURL.deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = directory
                .appendingPathComponent("script", isDirectory: true)
                .appendingPathComponent("install_hooks.py")
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }

        return nil
    }

    private func showHookInstallResult(_ result: HookInstallResult) {
        let alert = NSAlert()
        alert.alertStyle = result.succeeded ? .informational : .warning
        alert.messageText = result.succeeded ? "Integrations installed" : "Could not install integrations"
        alert.informativeText = result.informativeText
        alert.addButton(withTitle: "OK")
        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func renderMetrics(length: Double) -> RenderMetrics {
        let targetHeight = min(length, 22)
        let targetWidth = targetHeight * (Double(PetAtlasMetadata.cellWidth) / Double(PetAtlasMetadata.cellHeight))
        return RenderMetrics(spriteWidth: targetWidth, spriteHeight: targetHeight)
    }

    private func updateStatusDescription(
        animationState: PetAnimationState? = nil,
        attentionScope: CodexPetActiveScope? = nil
    ) {
        guard let button = statusItem.button else {
            return
        }

        let petName = selectedPet?.displayName ?? "Codex Pet"
        let state = animationState
            ?? preferences.manualAnimationState
            ?? currentActivity.animationState
        let stateDescription = isShowingCompletion ? "task finished" : isSleeping ? "sleeping" : state.rawValue.replacingOccurrences(of: "-", with: " ")
        let taskDescription: String
        switch runningThreadCount {
        case 0:
            taskDescription = "no active tasks"
        case 1:
            taskDescription = "1 active task"
        default:
            taskDescription = "\(runningThreadCount) active tasks"
        }
        let providerDescription = activeProviderDescription.map { ", \($0)" } ?? ""
        let attentionDescription = attentionScope.map {
            ", \(providerDisplayName($0.provider)) attention flag"
        } ?? ""
        let description = "\(petName), \(stateDescription)\(attentionDescription), \(taskDescription)\(providerDescription)"

        button.toolTip = description
        button.setAccessibilityLabel(petName)
        button.setAccessibilityValue("\(stateDescription), \(taskDescription)\(providerDescription)")
    }

    private var activeProviderDescription: String? {
        guard !activeScopes.isEmpty else {
            return nil
        }

        let scopesByProvider = Dictionary(grouping: activeScopes, by: \.provider)
        return PetProvider.allCases.compactMap { provider in
            guard let scopes = scopesByProvider[provider], !scopes.isEmpty else {
                return nil
            }
            let name = providerDisplayName(provider)
            let activities = Dictionary(grouping: scopes, by: \.activity)
            let details = [CodexActivity.reviewing, .failed, .running, .listening]
                .compactMap { activity -> String? in
                    guard let count = activities[activity]?.count, count > 0 else {
                        return nil
                    }
                    let label: String
                    switch activity {
                    case .reviewing:
                        label = "waiting"
                    case .failed:
                        label = "failed"
                    case .running:
                        label = "running"
                    case .listening:
                        label = "listening"
                    case .idle:
                        return nil
                    }
                    return count == 1 ? label : "\(count) \(label)"
                }
                .joined(separator: ", ")
            return details.isEmpty ? name : "\(name): \(details)"
        }
        .joined(separator: "; ")
    }

    private func providerDisplayName(_ provider: PetProvider) -> String {
        switch provider {
        case .codex:
            "Codex"
        case .claude:
            "Claude Code"
        case .cursor:
            "Cursor"
        }
    }

    private func applyStatusLength(_ length: Double) {
        guard lastAppliedStatusLength != length else {
            return
        }

        statusItem.length = length
        lastAppliedStatusLength = length
    }

    private func desiredTimerInterval() -> TimeInterval {
        if reduceMotion {
            return attentionPresentations.activeScope == nil && !isShowingCompletion
                ? RuntimeCadence.maintenanceInterval
                : RuntimeCadence.reducedMotionAttentionInterval
        }

        if spriteSheet == nil {
            return RuntimeCadence.maintenanceInterval
        }

        if preferences.manualAnimationState != nil {
            return RuntimeCadence.activeFrameInterval
        }

        if isSleeping {
            return RuntimeCadence.maintenanceInterval
        }

        return RuntimeCadence.activeFrameInterval
    }

    private func updateTimerCadenceIfNeeded() {
        let interval = desiredTimerInterval()
        guard currentTimerInterval != interval else {
            return
        }

        startTimer()
    }

    private func resetAnimationRuntime() {
        runtime = nil
        runtimeLayout = nil
        manualFrameClock.reset()
        lastFrameDate = nil
        lastRenderKey = nil
        attentionPresentationWasActive = false
        approvalRequestedForNextFrame = attentionPresentations.activeScope != nil
            && attentionRepeatCooldownRemaining == 0
        staticImageCache.removeAll(keepingCapacity: true)
        isDisplayingFallback = false
    }

    private func triggerReaction(_ state: PetAnimationState, duration: Double = 1.2) {
        reactionState = state
        reactionRemaining = duration
        updateCursorGazeMonitoring()
        updateTimerCadenceIfNeeded()
    }

    private func advanceReaction(deltaTime: Double) {
        guard reactionRemaining > 0, reactionState != nil else {
            self.reactionState = nil
            reactionRemaining = 0
            return
        }

        reactionRemaining = max(0, reactionRemaining - max(0, deltaTime))
        if reactionRemaining == 0 {
            self.reactionState = nil
            updateCursorGazeMonitoring()
        }
    }

    private var shouldTrackCursorGaze: Bool {
        !isSleeping && PetCursorGazePolicy.shouldTrack(
            spriteVersionNumber: selectedPet?.spriteVersionNumber ?? 1,
            activity: currentActivity,
            hasActiveThreads: runningThreadCount > 0,
            manualAnimationState: preferences.manualAnimationState,
            hasReaction: reactionState != nil || reactionRemaining > 0 || isShowingCompletion,
            approvalRequested: approvalRequestedForNextFrame
                || attentionPresentations.activeScope != nil
                || attentionPresentationWasActive,
            reduceMotion: reduceMotion
        ) && spriteSheet != nil
    }

    private func updateCursorGazeMonitoring() {
        guard shouldTrackCursorGaze else {
            stopCursorGazeMonitoring()
            return
        }

        guard !cursorGazeMonitoringActive else {
            return
        }

        cursorGazeMonitoringActive = true
        cursorGazeGeneration &+= 1
        cursorGazeLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.queueCursorGaze(location: NSEvent.mouseLocation)
            return event
        }
        cursorGazeGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.queueCursorGaze(location: NSEvent.mouseLocation)
        }
        refreshCursorGazeForCurrentPointer()
    }

    private func stopCursorGazeMonitoring() {
        guard cursorGazeMonitoringActive || cursorGazeHeadingIndex != nil else {
            return
        }

        cursorGazeMonitoringActive = false
        cursorGazeGeneration &+= 1
        if let cursorGazeLocalMonitor {
            NSEvent.removeMonitor(cursorGazeLocalMonitor)
            self.cursorGazeLocalMonitor = nil
        }
        if let cursorGazeGlobalMonitor {
            NSEvent.removeMonitor(cursorGazeGlobalMonitor)
            self.cursorGazeGlobalMonitor = nil
        }
        cursorGazeWorkItem?.cancel()
        cursorGazeWorkItem = nil
        pendingCursorLocation = nil
        lastCursorGazeRenderTime = nil
        if cursorGazeHeadingIndex != nil {
            cursorGazeHeadingIndex = nil
            lastRenderKey = nil
        }
    }

    private func refreshCursorGazeForCurrentPointer() {
        guard cursorGazeMonitoringActive else {
            return
        }
        queueCursorGaze(location: NSEvent.mouseLocation)
    }

    private func queueCursorGaze(location: NSPoint) {
        guard shouldTrackCursorGaze else {
            updateCursorGazeMonitoring()
            return
        }

        pendingCursorLocation = location
        guard cursorGazeWorkItem == nil else {
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        let delay = PetCursorGazePolicy.coalescingDelay(
            lastRenderTime: lastCursorGazeRenderTime,
            now: now,
            minimumInterval: RuntimeCadence.cursorGazeMinimumInterval
        )
        let generation = cursorGazeGeneration
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.flushCursorGaze(generation: generation)
            }
        }
        cursorGazeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func flushCursorGaze(generation: Int) {
        cursorGazeWorkItem = nil
        guard
            generation == cursorGazeGeneration,
            shouldTrackCursorGaze,
            let location = pendingCursorLocation,
            let center = currentPetScreenCenter()
        else {
            return
        }

        pendingCursorLocation = nil
        lastCursorGazeRenderTime = ProcessInfo.processInfo.systemUptime
        let update = PetCursorGazePolicy.update(
            x: location.x - center.x,
            y: location.y - center.y,
            previousHeadingIndex: cursorGazeHeadingIndex,
            deadzone: 1
        )
        guard update.shouldRender else {
            return
        }

        cursorGazeHeadingIndex = update.headingIndex
        lastRenderKey = nil
        renderCurrentFrame()
        updateTimerCadenceIfNeeded()
    }

    private func currentPetScreenCenter() -> NSPoint? {
        guard let button = statusItem.button, let window = button.window else {
            return nil
        }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRectOnScreen = window.convertToScreen(buttonRectInWindow)
        guard let lastRenderKey else {
            return NSPoint(x: buttonRectOnScreen.midX, y: buttonRectOnScreen.midY)
        }

        let metrics = renderMetrics(length: preferences.petSize.menuBarLength)
        return NSPoint(
            x: buttonRectOnScreen.minX + lastRenderKey.positionX + metrics.spriteWidth / 2,
            y: buttonRectOnScreen.midY
        )
    }

    private func staticImageKey(for renderKey: RenderKey) -> StaticImageKey? {
        let metrics = renderMetrics(length: preferences.petSize.menuBarLength)
        let compactWidth = PetMenuBarPresentation.sleepingWidth(spriteWidth: metrics.spriteWidth)
        let centeredPosition = (compactWidth - metrics.spriteWidth) / 2
        guard
            !renderKey.isSleeping,
            !renderKey.showsCompletion,
            renderKey.activeScopes.isEmpty,
            renderKey.attentionScope == nil,
            renderKey.scale == 1,
            renderKey.length == compactWidth,
            abs(renderKey.positionX - centeredPosition) < 0.001
        else {
            return nil
        }

        return StaticImageKey(
            petID: renderKey.petID,
            animationState: renderKey.animationState.rawValue,
            frameIndex: renderKey.frameIndex,
            directionalHeadingIndex: renderKey.directionalHeadingIndex,
            length: renderKey.length
        )
    }

    private func scaledImage(
        _ image: NSImage,
        length: Double,
        playfieldLength: Double,
        positionX: Double,
        scale: Double,
        activeScopes: [CodexPetActiveScope],
        attentionScope: CodexPetActiveScope?,
        threadDotPhase: Double,
        isDarkAppearance: Bool,
        isSleeping: Bool = false,
        showsCompletion: Bool = false
    ) -> NSImage {
        let metrics = renderMetrics(length: playfieldLength)
        let targetSize = NSSize(width: length, height: metrics.spriteHeight)
        let contentWidth = length - (showsCompletion ? PetMenuBarPresentation.completionAccessoryWidth : 0)
        let providerIndicators = PetMenuBarPresentation.providerIndicators(for: activeScopes)
        let flagsWidth = PetMenuBarPresentation.providerWidth(count: providerIndicators.count)
        let petPlayfieldWidth = contentWidth - flagsWidth
        let output = NSImage(size: targetSize)
        let clampedScale = max(0.1, scale)
        let drawWidth = metrics.spriteWidth * clampedScale
        let drawHeight = metrics.spriteHeight * clampedScale
        let drawOriginY = attentionScope != nil && clampedScale > 1
            ? metrics.spriteHeight - (drawHeight * RuntimeCadence.attentionVisibleTopRatio)
            : (metrics.spriteHeight - drawHeight) / 2
        let drawRect = NSRect(
            x: positionX - ((drawWidth - metrics.spriteWidth) / 2),
            y: drawOriginY,
            width: drawWidth,
            height: drawHeight
        )
        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        image.draw(in: drawRect)
        if isSleeping {
            drawSleepMarks(in: targetSize, isDarkAppearance: isDarkAppearance)
        }
        if let attentionScope {
            drawHeldProviderFlag(
                for: attentionScope,
                in: NSSize(width: petPlayfieldWidth, height: targetSize.height),
                nextTo: drawRect,
                isDarkAppearance: isDarkAppearance
            )
        }
        drawProviderFlags(
            providerIndicators,
            originX: petPlayfieldWidth,
            phase: threadDotPhase,
            outputHeight: metrics.spriteHeight,
            isDarkAppearance: isDarkAppearance
        )
        if showsCompletion { drawCompletion(in: targetSize, isDarkAppearance: isDarkAppearance) }
        output.unlockFocus()
        output.isTemplate = false
        return output
    }

    private func drawHeldProviderFlag(
        for scope: CodexPetActiveScope,
        in outputSize: NSSize,
        nextTo petRect: NSRect,
        isDarkAppearance: Bool
    ) {
        let flagWidth: CGFloat = 20
        let flagHeight: CGFloat = 12
        let poleX = min(
            max(petRect.maxX - 4, 2),
            outputSize.width - flagWidth - 3
        )
        let poleBottom = max(2, petRect.minY + 3)
        let poleHeight = min(outputSize.height - poleBottom - 1, flagHeight + 7)
        let flagY = min(poleBottom + 6, outputSize.height - flagHeight - 1)
        let flagRect = NSRect(
            x: poleX + 1,
            y: flagY,
            width: flagWidth,
            height: flagHeight
        )

        let poleColor = isDarkAppearance
            ? NSColor.white.withAlphaComponent(0.88)
            : NSColor(calibratedWhite: 0.16, alpha: 0.94)
        poleColor.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: poleX, y: poleBottom, width: 1.4, height: poleHeight),
            xRadius: 0.7,
            yRadius: 0.7
        ).fill()

        let flagPath = NSBezierPath()
        flagPath.move(to: flagRect.origin)
        flagPath.curve(
            to: NSPoint(x: flagRect.maxX, y: flagRect.minY + 1.6),
            controlPoint1: NSPoint(x: flagRect.minX + flagRect.width * 0.34, y: flagRect.minY + 2.2),
            controlPoint2: NSPoint(x: flagRect.maxX - 3, y: flagRect.minY - 1)
        )
        flagPath.line(to: NSPoint(x: flagRect.maxX - 2.1, y: flagRect.midY))
        flagPath.line(to: NSPoint(x: flagRect.maxX, y: flagRect.maxY - 1.4))
        flagPath.curve(
            to: NSPoint(x: flagRect.minX, y: flagRect.maxY),
            controlPoint1: NSPoint(x: flagRect.maxX - 4.4, y: flagRect.maxY + 1.7),
            controlPoint2: NSPoint(x: flagRect.minX + flagRect.width * 0.4, y: flagRect.maxY - 1.2)
        )
        flagPath.close()

        NSGraphicsContext.saveGraphicsState()
        flagPath.addClip()
        heldFlagGradient(for: scope.provider)?.draw(in: flagRect, angle: -84)
        NSColor.white.withAlphaComponent(0.22).setFill()
        NSBezierPath(
            roundedRect: flagRect.insetBy(dx: 1, dy: flagRect.height * 0.61),
            xRadius: 2,
            yRadius: 2
        ).fill()
        NSGraphicsContext.restoreGraphicsState()

        heldFlagStrokeColor(for: scope).setStroke()
        flagPath.lineWidth = 0.75
        flagPath.stroke()

        let iconIsDark = scope.provider == .codex
        let iconDimension: CGFloat = scope.provider == .claude ? 10 : 9.4
        if let icon = ProviderBrandImages.statusFlagImage(
            for: scope.provider,
            isDark: iconIsDark,
            dimension: iconDimension
        ) {
            let iconRect = NSRect(
                x: flagRect.minX + 3.1,
                y: flagRect.midY - (iconDimension / 2),
                width: iconDimension,
                height: iconDimension
            )
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.imageInterpolation = .high
            icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }

    }

    private func heldFlagGradient(for provider: PetProvider) -> NSGradient? {
        switch provider {
        case .codex:
            NSGradient(colors: [
                NSColor(calibratedRed: 0.43, green: 0.48, blue: 1, alpha: 0.98),
                NSColor(calibratedRed: 0.20, green: 0.25, blue: 0.86, alpha: 0.98),
            ])
        case .claude:
            NSGradient(colors: [
                NSColor(calibratedRed: 1, green: 0.95, blue: 0.91, alpha: 0.98),
                NSColor(calibratedRed: 1, green: 0.82, blue: 0.72, alpha: 0.98),
            ])
        case .cursor:
            NSGradient(colors: [
                NSColor(calibratedWhite: 1, alpha: 0.98),
                NSColor(calibratedWhite: 0.82, alpha: 0.98),
            ])
        }
    }

    private func heldFlagStrokeColor(for scope: CodexPetActiveScope) -> NSColor {
        if scope.activity == .failed {
            return .systemRed
        }
        return switch scope.provider {
        case .codex:
            NSColor(calibratedRed: 0.22, green: 0.28, blue: 0.90, alpha: 0.92)
        case .claude:
            NSColor(calibratedRed: 0.78, green: 0.30, blue: 0.18, alpha: 0.92)
        case .cursor:
            NSColor(calibratedWhite: 0.32, alpha: 0.88)
        }
    }

    private func drawProviderFlags(
        _ scopes: [CodexPetActiveScope],
        originX: Double,
        phase: Double,
        outputHeight: Double,
        isDarkAppearance: Bool
    ) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.imageInterpolation = .high
        for (index, scope) in scopes.enumerated() {
            let diameter = PetMenuBarPresentation.providerIconWidth
            let x = originX + PetMenuBarPresentation.providerLeadingGap
                + Double(index) * (diameter + PetMenuBarPresentation.providerGap)
            let iconRect = NSRect(x: x, y: (outputHeight - diameter) / 2, width: diameter, height: diameter)
            if let color = providerFlagEmphasisColor(activity: scope.activity) {
                let ring = NSBezierPath(roundedRect: iconRect.insetBy(dx: -1.5, dy: -1.5), xRadius: 5, yRadius: 5)
                color.withAlphaComponent(isDarkAppearance ? 0.20 : 0.12).setFill()
                ring.fill()
                color.withAlphaComponent(0.8).setStroke()
                ring.lineWidth = 0.7
                ring.stroke()
            }
            guard let providerImage = ProviderBrandImages.statusFlagImage(
                for: scope.provider,
                isDark: isDarkAppearance,
                dimension: diameter
            ) else { continue }
            providerImage.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func providerFlagEmphasisColor(activity: CodexActivity) -> NSColor? {
        switch activity {
        case .reviewing:
            return .systemOrange
        case .failed:
            return .systemRed
        case .idle, .listening, .running:
            return nil
        }
    }

    private func drawCompletion(in outputSize: NSSize, isDarkAppearance: Bool) {
        let startX = outputSize.width - PetMenuBarPresentation.completionAccessoryWidth + 4
        let color = isDarkAppearance
            ? NSColor(calibratedRed: 0.62, green: 0.92, blue: 0.66, alpha: 1)
            : NSColor(calibratedRed: 0.18, green: 0.48, blue: 0.26, alpha: 1)
        let checkRect = NSRect(x: startX, y: (outputSize.height - 11) / 2, width: 11, height: 11)
        color.setStroke()
        let check = NSBezierPath()
        check.lineWidth = 1.7
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        check.move(to: NSPoint(x: checkRect.minX + 1, y: checkRect.minY + 5))
        check.line(to: NSPoint(x: checkRect.minX + 4, y: checkRect.minY + 2))
        check.line(to: NSPoint(x: checkRect.minX + 10, y: checkRect.minY + 9))
        check.stroke()
        let label = "Done" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: color]
        let size = label.size(withAttributes: attributes)
        label.draw(at: NSPoint(x: checkRect.maxX + 3, y: (outputSize.height - size.height) / 2), withAttributes: attributes)
    }

    private func drawSleepMarks(in outputSize: NSSize, isDarkAppearance: Bool) {
        let ink = (isDarkAppearance ? NSColor.white : NSColor.black).withAlphaComponent(0.65)
        for (size, x, y) in [(3.5, outputSize.width - 7, outputSize.height - 9), (4.5, outputSize.width - 4, outputSize.height - 5)] {
            ("z" as NSString).draw(
                at: NSPoint(x: x, y: y),
                withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: ink]
            )
        }
    }

    /// Drives actual prompt/Stop events through the controller, including a second run.
    static func renderMenuBarStatesPreview(to url: URL) throws {
        let suiteName = "CodexPetBar.MenuBarStatesPreview.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { throw ProviderFlagPreviewError.renderFailed }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.followCodexPet = false
        preferences.selectedPetIDOverride = "mini-gandalf-the-grey"
        preferences.petSize = .large
        preferences.manualAnimationState = nil
        let renderScale: CGFloat = 4
        let cardWidth: CGFloat = 500
        let cardHeight: CGFloat = 134
        let rowCount = 11
        let output = NSImage(size: NSSize(width: cardWidth * 3, height: cardHeight * CGFloat(rowCount)))
        var report: [[String: Any]] = []
        output.lockFocus()
        do {
            for column in 0..<3 {
                let controller = StatusPetController(preferences: preferences)
                controller.refreshPets(playReaction: false)
                guard controller.spriteSheet != nil else { throw ProviderFlagPreviewError.renderFailed }
                controller.cachedPetEvents = []
                controller.reduceMotion = false
                let isDark = column != 0
                controller.statusItem.button?.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
                let baseTime = Date().timeIntervalSince1970
                var eventIndex = 0
                var row = 0
                func feed(_ kind: String, turn: String, hook: String, status: String? = nil) {
                    eventIndex += 1
                    controller.applyNewPetEvents([CodexPetEvent(
                        kind: kind,
                        timestamp: baseTime + Double(eventIndex) * 0.01,
                        provider: .codex,
                        sessionID: "preview-lifecycle-\(column)",
                        turnID: turn,
                        hookEventName: hook,
                        status: status
                    )])
                }
                func scanned(_ state: CodexRunningThreadLog.State, turn: String, outcome: CodexRunningThreadLog.CompletionOutcome? = nil) {
                    let scope = CodexRolloutActivityScope(
                        sessionID: "preview-lifecycle-\(column)",
                        modificationDate: Date().addingTimeInterval(30),
                        marker: .init(state: state, completionOutcome: outcome, turnID: turn,
                                      timestamp: baseTime + Double(eventIndex) * 0.01)
                    )
                    controller.verifiedRunningCodexScopes = state == .running ? [scope] : []
                    controller.verifiedCompletedCodexScopes = state == .completed ? [scope] : []
                }
                func paint(_ label: String, delta: Double = 0) throws {
                    controller.renderCurrentFrame(deltaTime: delta)
                    guard let image = controller.statusItem.button?.image, let key = controller.lastRenderKey else {
                        throw ProviderFlagPreviewError.renderFailed
                    }
                    let cardRect = NSRect(x: CGFloat(column) * cardWidth, y: CGFloat(rowCount - row - 1) * cardHeight, width: cardWidth, height: cardHeight)
                    let background = column == 2
                        ? NSColor(calibratedRed: 0.27, green: 0.50, blue: 0.70, alpha: 1)
                        : isDark ? NSColor(calibratedWhite: 0.09, alpha: 1) : NSColor(calibratedWhite: 0.96, alpha: 1)
                    background.setFill()
                    NSBezierPath(rect: cardRect).fill()
                    NSGraphicsContext.current?.imageInterpolation = .none
                    image.draw(in: NSRect(x: cardRect.minX + 16, y: cardRect.minY + 34, width: image.size.width * renderScale, height: image.size.height * renderScale))
                    ("\(label) · \(Int(image.size.width)) pt" as NSString).draw(
                        at: NSPoint(x: cardRect.minX + 16, y: cardRect.minY + 12),
                        withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: isDark ? NSColor.white : NSColor.black]
                    )
                    report.append([
                        "state": label, "background": column, "taskCount": controller.activeScopes.count,
                        "width": image.size.width, "height": image.size.height, "sleeping": key.isSleeping,
                        "frame": key.frameIndex, "x": key.positionX, "scale": key.scale,
                        "done": key.showsCompletion, "animation": key.animationState.rawValue,
                    ])
                    row += 1
                }
                try paint("Sleeping")
                feed("prompt_submitted", turn: "one", hook: "UserPromptSubmit")
                scanned(.running, turn: "one")
                try paint("Running · start", delta: 0.14)
                try paint("Running · later", delta: 0.7)
                feed("stopped", turn: "one", hook: "Stop", status: "completed")
                try paint("Task complete", delta: 0.4)
                scanned(.completed, turn: "one", outcome: .success)
                controller.expireCompletion(now: Date().addingTimeInterval(6))
                try paint("Back to sleep")
                feed("prompt_submitted", turn: "two", hook: "UserPromptSubmit")
                try paint("Runs again · start", delta: 0.14)
                try paint("Runs again · later", delta: 0.7)
                scanned(.running, turn: "two")
                feed("stopped", turn: "two", hook: "Stop", status: "completed")
                try paint("Second task complete", delta: 0.4)
                scanned(.completed, turn: "two", outcome: .success)
                feed("prompt_submitted", turn: "three", hook: "UserPromptSubmit")
                try paint("New work clears Done", delta: 0.14)
                feed("stopped", turn: "three", hook: "Stop", status: "aborted")
                try paint("Cancelled · no Done")
                controller.reduceMotion = true
                feed("prompt_submitted", turn: "four", hook: "UserPromptSubmit")
                feed("stopped", turn: "four", hook: "Stop", status: "completed")
                try paint("Done · reduced motion")
            }
        } catch {
            output.unlockFocus()
            throw error
        }
        output.unlockFocus()
        guard let tiff = output.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:]) else { throw ProviderFlagPreviewError.renderFailed }
        try png.write(to: url, options: .atomic)
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: url.deletingPathExtension().appendingPathExtension("json"), options: .atomic)
    }

    /// Deterministic app-only composition used to inspect the real menu-bar
    /// renderer without capturing unrelated desktop content.
    static func renderProviderFlagPreview(to url: URL) throws {
        let previousAppearance = NSApp.appearance
        NSApp.appearance = NSAppearance(named: .darkAqua)
        defer {
            NSApp.appearance = previousAppearance
        }
        let suiteName = "CodexPetBar.ProviderFlagPreview.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw ProviderFlagPreviewError.renderFailed
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let preferences = AppPreferences(defaults: defaults)
        preferences.followCodexPet = false
        preferences.selectedPetIDOverride = "grumble"
        preferences.petSize = .medium
        preferences.manualAnimationState = .idle

        let controller = StatusPetController(preferences: preferences)
        controller.statusItem.button?.appearance = NSAppearance(named: .darkAqua)
        controller.refreshPets(playReaction: false)
        controller.activeScopes = [
            CodexPetActiveScope(provider: .codex, scopedIdentity: "codex-a", activity: .running),
            CodexPetActiveScope(provider: .codex, scopedIdentity: "codex-b", activity: .reviewing),
            CodexPetActiveScope(provider: .claude, scopedIdentity: "claude-a", activity: .running),
            CodexPetActiveScope(provider: .claude, scopedIdentity: "claude-b", activity: .reviewing),
            CodexPetActiveScope(provider: .cursor, scopedIdentity: "cursor-a", activity: .running),
            CodexPetActiveScope(provider: .cursor, scopedIdentity: "cursor-b", activity: .failed),
        ]
        controller.runningThreadCount = controller.activeScopes.count
        controller.currentActivity = .reviewing
        controller.threadDotPhase = 0.7
        controller.renderCurrentFrame(deltaTime: 0)

        guard let statusImage = controller.statusItem.button?.image else {
            throw ProviderFlagPreviewError.renderFailed
        }
        let scale: CGFloat = 8
        let padding: CGFloat = 4
        let logicalSize = NSSize(
            width: statusImage.size.width + (padding * 2),
            height: statusImage.size.height + (padding * 2)
        )
        let output = NSImage(
            size: NSSize(width: logicalSize.width * scale, height: logicalSize.height * scale)
        )
        output.lockFocus()
        NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: output.size)).fill()
        NSGraphicsContext.current?.imageInterpolation = .none
        statusImage.draw(
            in: NSRect(
                x: padding * scale,
                y: padding * scale,
                width: statusImage.size.width * scale,
                height: statusImage.size.height * scale
            )
        )
        output.unlockFocus()

        guard
            let tiffData = output.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw ProviderFlagPreviewError.renderFailed
        }
        try pngData.write(to: url, options: .atomic)
    }

    /// Light/dark provider contact sheet rendered through the same sprite and
    /// flag compositor used by the live menu-bar item.
    static func renderAttentionFlagPreview(to url: URL) throws {
        let suiteName = "CodexPetBar.AttentionFlagPreview.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw ProviderFlagPreviewError.renderFailed
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = AppPreferences(defaults: defaults)
        preferences.followCodexPet = false
        preferences.selectedPetIDOverride = "grumble"
        preferences.petSize = .medium
        preferences.manualAnimationState = nil

        let controller = StatusPetController(preferences: preferences)
        controller.refreshPets(playReaction: false)
        guard let wavingFrame = controller.spriteSheet?.frames(for: .waving).first else {
            throw ProviderFlagPreviewError.renderFailed
        }

        let providers = PetProvider.allCases
        let appearances: [(name: String, isDark: Bool)] = [
            ("Light", false),
            ("Dark", true),
        ]
        let renderScale: CGFloat = 4
        let petWidth = PetMenuBarPresentation.sleepingWidth(spriteWidth: controller.renderMetrics(length: preferences.petSize.menuBarLength).spriteWidth)
        let attentionLength = petWidth + RuntimeCadence.heldFlagSpace
        let statusWidth = CGFloat(PetMenuBarPresentation.contentWidth(petWidth: attentionLength, providerCount: 1)
)
        let statusHeight = CGFloat(controller.renderMetrics(length: preferences.petSize.menuBarLength).spriteHeight)
        let cardPadding: CGFloat = 12
        let labelHeight: CGFloat = 20
        let cardWidth = (statusWidth * renderScale) + (cardPadding * 2)
        let cardHeight = (statusHeight * renderScale) + labelHeight + (cardPadding * 2)
        let output = NSImage(size: NSSize(
            width: cardWidth * CGFloat(providers.count),
            height: cardHeight * CGFloat(appearances.count)
        ))

        output.lockFocus()
        for (row, appearance) in appearances.enumerated() {
            for (column, provider) in providers.enumerated() {
                let cardRect = NSRect(
                    x: CGFloat(column) * cardWidth,
                    y: CGFloat(appearances.count - row - 1) * cardHeight,
                    width: cardWidth,
                    height: cardHeight
                )
                let background = appearance.isDark
                    ? NSColor(calibratedWhite: 0.09, alpha: 1)
                    : NSColor(calibratedWhite: 0.96, alpha: 1)
                background.setFill()
                NSBezierPath(rect: cardRect).fill()

                let activity: CodexActivity = provider == .cursor ? .failed : .reviewing
                let scope = CodexPetActiveScope(
                    provider: provider,
                    scopedIdentity: "preview-\(provider.rawValue)",
                    activity: activity
                )
                let baseMetrics = controller.renderMetrics(length: preferences.petSize.menuBarLength)
                let positionX = (petWidth - baseMetrics.spriteWidth) / 2
                let statusImage = controller.scaledImage(
                    wavingFrame,
                    length: Double(statusWidth),
                    playfieldLength: preferences.petSize.menuBarLength,
                    positionX: positionX,
                    scale: 1,
                    activeScopes: [scope],
                    attentionScope: scope,
                    threadDotPhase: 0.7,
                    isDarkAppearance: appearance.isDark
                )
                NSGraphicsContext.current?.imageInterpolation = .none
                statusImage.draw(in: NSRect(
                    x: cardRect.minX + cardPadding,
                    y: cardRect.minY + cardPadding + labelHeight,
                    width: statusWidth * renderScale,
                    height: statusHeight * renderScale
                ))

                let providerName = switch provider {
                case .codex: "Codex"
                case .claude: "Claude Code"
                case .cursor: "Cursor"
                }
                let label = "\(appearance.name) · \(providerName)" as NSString
                label.draw(
                    at: NSPoint(x: cardRect.minX + cardPadding, y: cardRect.minY + cardPadding),
                    withAttributes: [
                        .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                        .foregroundColor: appearance.isDark ? NSColor.white : NSColor.black,
                    ]
                )
            }
        }
        output.unlockFocus()

        guard
            let tiffData = output.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw ProviderFlagPreviewError.renderFailed
        }
        try pngData.write(to: url, options: .atomic)
    }

}

private enum ProviderFlagPreviewError: Error {
    case renderFailed
}

private enum RuntimeCadence {
    static let activeFrameInterval: TimeInterval = 0.14
    static let idleFrameInterval: TimeInterval = 0.5
    static let reducedMotionAttentionInterval: TimeInterval = 0.5
    static let hookSnapshotRefreshInterval: TimeInterval = 5
    static let maintenanceInterval: TimeInterval = 5
    static let activeRolloutScanInterval: TimeInterval = 4
    static let idleRolloutScanInterval: TimeInterval = 4
    static let rolloutActivityStaleWindow: TimeInterval = 60 * 60
    static let maximumRolloutScanThreadCount = 80
    static let hookReviewWindow: TimeInterval = 7 * 24 * 60 * 60
    static let maximumCachedPetEvents = 4_096
    static let maximumStaticImageCacheEntries = 128
    static let cursorGazeMinimumInterval: TimeInterval = 0.05
    static let attentionPresentationDuration: TimeInterval = 2.4
    static let attentionRepeatCooldown: TimeInterval = 12
    static let heldFlagSpace: Double = 22
    static let attentionVisibleTopRatio: Double = 0.88
}

private struct PetEventIncrementalRead: Sendable {
    let events: [CodexPetEvent]
    let nextOffset: UInt64
    let wasReset: Bool
    let didFail: Bool
}

private struct PetRuntimeLayout: Equatable {
    let playfieldWidth: Double
    let spriteWidth: Double
}

private struct RenderMetrics {
    let spriteWidth: Double
    let spriteHeight: Double
}

private struct RenderState {
    let animationState: PetAnimationState
    let frameIndex: Int
    let positionX: Double
    let scale: Double
    let length: Double
    let attentionScope: CodexPetActiveScope?
    var isSleeping: Bool = false
}

private struct RenderKey: Equatable {
    let petID: String?
    let animationState: PetAnimationState
    let frameIndex: Int
    let directionalHeadingIndex: Int?
    let length: Double
    let positionX: Double
    let scale: Double
    let activeScopes: [CodexPetActiveScope]
    let attentionScope: CodexPetActiveScope?
    let isDarkAppearance: Bool
    let threadDotPhase: Double
    let isSleeping: Bool
    let showsCompletion: Bool
}

private struct StaticImageKey: Hashable {
    let petID: String?
    let animationState: String
    let frameIndex: Int
    let directionalHeadingIndex: Int?
    let length: Double
}

private struct ThreadIndexSignature: Equatable {
    let fileSize: UInt64
    let modificationDate: Date?
}

private struct HookInstallResult: Sendable {
    let exitCode: Int32
    let output: String
    let error: String
    let launchError: String?

    var succeeded: Bool {
        launchError == nil && exitCode == 0
    }

    var informativeText: String {
        if let launchError {
            return launchError
        }

        let details = [output, error]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        if details.isEmpty {
            return succeeded
                ? "Installed global hooks into ~/.codex/hooks.json."
                : "The hook installer exited with status \(exitCode)."
        }

        return details
    }
}

private enum HookInstaller {
    static func run(installerURL: URL, provider: String) -> HookInstallResult {
        let result = BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: [installerURL.path, "--provider", provider]
        )
        return HookInstallResult(
            exitCode: result.exitCode,
            output: result.output,
            error: result.error,
            launchError: result.failure
        )
    }
}

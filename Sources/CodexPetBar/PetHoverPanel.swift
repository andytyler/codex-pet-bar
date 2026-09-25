import AppKit
import CodexPetBarCore
import SwiftUI

private enum PetHoverPanelMetrics {
    static let width: CGFloat = 420
    static let screenMargin: CGFloat = 8
    static let statusGap: CGFloat = 6
    static let showDelay: TimeInterval = 0.18
    static let hideDelay: TimeInterval = 0.30
    static let fadeDuration: TimeInterval = 0.12
}

@MainActor
final class PetHoverPanelController: NSObject {
    typealias ContentProvider = @MainActor () -> PetHoverPanelContent
    typealias TaskHandler = @MainActor (PetTaskPresentation) -> Void

    private weak var statusButton: NSStatusBarButton?
    private var statusTrackingView: PetHoverTrackingView?
    private var hostingView: NSHostingView<PetHoverPanelView>?
    private var panelTrackingContainer: PetPanelTrackingContainer?
    private var contentProvider: ContentProvider?
    private var taskHandler: TaskHandler?
    private var showWorkItem: DispatchWorkItem?
    private var hideWorkItem: DispatchWorkItem?
    private var transitionGeneration = 0
    private var dismissalPolicy = PetHoverDismissalPolicy()
    private var isPointerOverStatusItem = false
    private var isPointerOverPanel = false
    private var isMenuOpen = false
    private var isPinned = false
    private var showsConnections = false
    private var settingsHandler: (@MainActor () -> Void)?
    private var connectionHandler: (@MainActor (PetProvider) -> Void)?
    private var modeHandler: (@MainActor (PetDisplayMode) -> Void)?
    private var assignmentHandler: (@MainActor (String, String) -> Void)?
    private var localDismissMonitor: Any?
    private var globalDismissMonitor: Any?

    private lazy var panel: NSPanel = {
        let panel = PetTaskPanel(
            contentRect: .zero,
            styleMask: ProcessInfo.processInfo.arguments.contains("--preview-task-panel")
                ? [.titled, .closable] : [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.title = ProcessInfo.processInfo.arguments.contains("--preview-task-panel") ? "Pet Bar Preview" : "Pet Bar"
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.setAccessibilitySubrole(.dialog)
        panel.setAccessibilityLabel("Pet task summaries")
        return panel
    }()

    isolated deinit {
        showWorkItem?.cancel()
        hideWorkItem?.cancel()
        if let localDismissMonitor { NSEvent.removeMonitor(localDismissMonitor) }
        if let globalDismissMonitor { NSEvent.removeMonitor(globalDismissMonitor) }
    }

    func attach(
        to statusButton: NSStatusBarButton,
        contentProvider: @escaping ContentProvider,
        onOpenTask: @escaping TaskHandler,
        onOpenSettings: @escaping @MainActor () -> Void,
        onConnect: @escaping @MainActor (PetProvider) -> Void,
        onChangeMode: @escaping @MainActor (PetDisplayMode) -> Void,
        onAssignPet: @escaping @MainActor (String, String) -> Void
    ) {
        self.statusButton = statusButton
        self.contentProvider = contentProvider
        self.taskHandler = onOpenTask
        self.settingsHandler = onOpenSettings
        self.connectionHandler = onConnect
        self.modeHandler = onChangeMode
        self.assignmentHandler = onAssignPet

        statusTrackingView?.removeFromSuperview()
        let trackingView = PetHoverTrackingView(frame: statusButton.bounds)
        trackingView.autoresizingMask = [.width, .height]
        trackingView.onEnter = { [weak self] in
            self?.statusPointerDidEnter()
        }
        trackingView.onExit = { [weak self] in
            self?.statusPointerDidExit()
        }
        statusButton.addSubview(trackingView, positioned: .above, relativeTo: nil)
        statusTrackingView = trackingView
    }

    var isVisible: Bool { panel.isVisible }

    func contentDidChange() {
        guard panel.isVisible else {
            return
        }
        updatePanelContentAndPosition()
    }

    func menuWillOpen() {
        isMenuOpen = true
        cancelScheduledTransitions()
        hideImmediately()
    }

    func menuDidClose() {
        isMenuOpen = false
        refreshPointerOwnership()
        if isPointerOverStatusItem {
            scheduleShow()
        }
    }

    func togglePinned() {
        if panel.isVisible && isPinned {
            dismiss()
            return
        }
        presentPinned()
    }

    func presentConnections() {
        showsConnections = true
        presentPinned()
    }

    func presentPinned() {
        guard !isMenuOpen else { return }
        cancelScheduledTransitions()
        cancelFadeOut()
        isPinned = true
        updatePanelContentAndPosition()
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        startDismissMonitors()
    }

    private func pinForInteraction() {
        cancelScheduledTransitions()
        cancelFadeOut()
        isPinned = true
        panel.makeKeyAndOrderFront(nil)
        startDismissMonitors()
    }

    private func startDismissMonitors() {
        guard localDismissMonitor == nil else { return }
        localDismissMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 && self.panel.isKeyWindow {
                    self.dismiss()
                    return nil
                }
            } else if event.window == nil || event.window === self.panel {
                self.dismissIfOutside()
            }
            return event
        }
        globalDismissMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.dismissIfOutside()
        }
    }

    private func dismissIfOutside() {
        let point = NSEvent.mouseLocation
        guard !panel.frame.contains(point), statusButtonScreenRect()?.contains(point) != true else { return }
        dismiss()
    }

    private func stopDismissMonitors() {
        if let localDismissMonitor { NSEvent.removeMonitor(localDismissMonitor) }
        if let globalDismissMonitor { NSEvent.removeMonitor(globalDismissMonitor) }
        localDismissMonitor = nil
        globalDismissMonitor = nil
    }

    func dismiss() {
        isPointerOverPanel = false
        cancelScheduledTransitions()
        hideImmediately()
    }

    /// Launch-only visual QA seam. Normal users reach the same surface by
    /// hovering the status item; `--preview-task-panel` makes capture reliable.
    func presentPreview() {
        guard !isMenuOpen else {
            return
        }
        cancelScheduledTransitions()
        updatePanelContentAndPosition()
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        isPinned = true
        startDismissMonitors()
    }

    private func statusPointerDidEnter() {
        isPointerOverStatusItem = true
        cancelFadeOut()
        hideWorkItem?.cancel()
        hideWorkItem = nil
        scheduleShow()
    }

    private func statusPointerDidExit() {
        isPointerOverStatusItem = false
        scheduleHideIfUnowned()
    }

    private func panelPointerDidEnter() {
        isPointerOverPanel = true
        cancelFadeOut()
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    private func panelPointerDidExit() {
        isPointerOverPanel = false
        scheduleHideIfUnowned()
    }

    private func scheduleShow() {
        guard !isMenuOpen, !panel.isVisible, showWorkItem == nil else {
            return
        }

        transitionGeneration &+= 1
        let generation = transitionGeneration
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, generation == self.transitionGeneration else {
                    return
                }
                self.showWorkItem = nil
                self.showIfEligible()
            }
        }
        showWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + PetHoverPanelMetrics.showDelay,
            execute: workItem
        )
    }

    private func scheduleHideIfUnowned() {
        guard !isPinned, !isPointerOverStatusItem, !isPointerOverPanel else {
            return
        }

        showWorkItem?.cancel()
        showWorkItem = nil
        guard panel.isVisible, hideWorkItem == nil else {
            return
        }

        transitionGeneration &+= 1
        let generation = transitionGeneration
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, generation == self.transitionGeneration else {
                    return
                }
                self.hideWorkItem = nil
                self.hideAnimated()
            }
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + PetHoverPanelMetrics.hideDelay,
            execute: workItem
        )
    }

    private func showIfEligible() {
        guard !isMenuOpen, isPointerOverStatusItem else {
            return
        }

        updatePanelContentAndPosition()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = reduceMotion ? 1 : 0
        panel.orderFrontRegardless()

        guard !reduceMotion else {
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = PetHoverPanelMetrics.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func updatePanelContentAndPosition() {
        guard let contentProvider, let statusRect = statusButtonScreenRect() else {
            return
        }

        let content = contentProvider()
        let screen = statusButton?.window?.screen
            ?? NSScreen.screens.first(where: { $0.frame.intersects(statusRect) })
            ?? NSScreen.main
        guard let screen else {
            return
        }

        let availableHeight = max(132, screen.visibleFrame.height - (2 * PetHoverPanelMetrics.screenMargin))
        let connectionHeight: CGFloat = showsConnections
            ? ProviderConnectionsView.estimatedHeight(resultMessage: content.connectionMessage) + 38 : 0
        let panelHeight = min(content.preferredHeight + connectionHeight, availableHeight)
        let rootView = PetHoverPanelView(
            content: content,
            height: panelHeight,
            onOpenTask: { [weak self] task in
                self?.presentPinned()
                self?.taskHandler?(task)
            },
            showsConnections: showsConnections,
            onToggleConnections: { [weak self] in
                guard let self else { return }
                self.showsConnections.toggle()
                self.presentPinned()
            },
            onOpenSettings: { [weak self] in
                self?.dismiss()
                self?.settingsHandler?()
            },
            onConnect: { [weak self] provider in
                self?.presentPinned()
                self?.connectionHandler?(provider)
            },
            onChangeMode: { [weak self] mode in
                self?.modeHandler?(mode)
                self?.presentPinned()
            },
            onAssignPet: { [weak self] taskID, petID in
                self?.assignmentHandler?(taskID, petID)
                self?.presentPinned()
            },
            onBeginInteraction: { [weak self] in self?.pinForInteraction() }
        )

        if let hostingView {
            hostingView.rootView = rootView
        } else {
            let hostingView = NSHostingView(rootView: rootView)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            let container = PetPanelTrackingContainer(frame: .zero)
            container.onEnter = { [weak self] in
                self?.panelPointerDidEnter()
            }
            container.onExit = { [weak self] in
                self?.panelPointerDidExit()
            }
            container.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: container.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            panel.contentView = container
            self.hostingView = hostingView
            panelTrackingContainer = container
        }

        let frame = panelFrame(
            statusRect: statusRect,
            visibleFrame: screen.visibleFrame,
            size: NSSize(width: PetHoverPanelMetrics.width, height: panelHeight)
        )
        panel.setFrame(frame, display: panel.isVisible)
    }

    private func panelFrame(statusRect: NSRect, visibleFrame: NSRect, size: NSSize) -> NSRect {
        let proposedX = statusRect.midX - (size.width / 2)
        let maximumX = visibleFrame.maxX - size.width - PetHoverPanelMetrics.screenMargin
        let x = min(
            max(proposedX, visibleFrame.minX + PetHoverPanelMetrics.screenMargin),
            max(visibleFrame.minX + PetHoverPanelMetrics.screenMargin, maximumX)
        )

        let proposedTop = min(
            statusRect.minY - PetHoverPanelMetrics.statusGap,
            visibleFrame.maxY - PetHoverPanelMetrics.screenMargin
        )
        let y = max(
            visibleFrame.minY + PetHoverPanelMetrics.screenMargin,
            proposedTop - size.height
        )
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    private func hideAnimated() {
        guard panel.isVisible, !isPinned else {
            return
        }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            hideImmediately()
            return
        }

        transitionGeneration &+= 1
        let generation = transitionGeneration
        let fadeToken = dismissalPolicy.beginFade()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = PetHoverPanelMetrics.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, generation == self.transitionGeneration else {
                    return
                }
                self.refreshPointerOwnership()
                guard self.dismissalPolicy.finishFade(
                    fadeToken,
                    pointerOwnsSurface: self.isPinned || self.isPointerOverStatusItem || self.isPointerOverPanel
                ) else {
                    self.panel.alphaValue = 1
                    return
                }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
        }
    }

    private func hideImmediately() {
        isPinned = false
        stopDismissMonitors()
        dismissalPolicy.cancelFade()
        transitionGeneration &+= 1
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    private func cancelScheduledTransitions() {
        transitionGeneration &+= 1
        showWorkItem?.cancel()
        showWorkItem = nil
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    private func cancelFadeOut() {
        guard dismissalPolicy.cancelFade() else { return }
        transitionGeneration &+= 1
        // Replace the old animator target as well as invalidating its completion.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
    }

    private func refreshPointerOwnership() {
        let location = NSEvent.mouseLocation
        isPointerOverStatusItem = statusButtonScreenRect()?.contains(location) == true
        isPointerOverPanel = panel.isVisible && panel.frame.contains(location)
    }

    private func statusButtonScreenRect() -> NSRect? {
        guard let statusButton, let window = statusButton.window else {
            return nil
        }
        let rectInWindow = statusButton.convert(statusButton.bounds, to: nil)
        return window.convertToScreen(rectInWindow)
    }
}

private final class PetTaskPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }
}

private final class PetHoverTrackingView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        onExit?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private final class PetPanelTrackingContainer: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        onExit?()
    }
}

struct PetHoverPanelView: View {
    let content: PetHoverPanelContent
    let height: CGFloat
    let onOpenTask: (PetTaskPresentation) -> Void
    var showsConnections = false
    var onToggleConnections: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onConnect: (PetProvider) -> Void = { _ in }
    var onChangeMode: (PetDisplayMode) -> Void = { _ in }
    var onAssignPet: (String, String) -> Void = { _, _ in }
    var onBeginInteraction: () -> Void = {}
    @State private var search = ""
    @State private var showsRecent = false
    @FocusState private var searchIsFocused: Bool

    private var tasks: [PetTaskPresentation] {
        content.projects.flatMap { project in
            project.tasks.map { task in
                var row = task
                if row.projectName.isEmpty { row.projectName = project.name }
                return row
            }
        }
    }
    private var filtered: [PetTaskPresentation] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? tasks : tasks.filter {
            "\($0.title) \($0.summary) \($0.projectName) \($0.provider.displayName)".localizedCaseInsensitiveContains(query)
        }
    }
    private var attention: [PetTaskPresentation] { filtered.filter { $0.state == .waiting || $0.state == .failed } }
    private var working: [PetTaskPresentation] { filtered.filter { $0.state == .running } }
    private var recent: [PetTaskPresentation] { filtered.filter { !$0.state.isActive } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Picker("Menu bar mode", selection: Binding(get: { content.displayMode }, set: { onChangeMode($0) })) {
                Text("One companion").tag(PetDisplayMode.companion)
                Text("Pets per task").tag(PetDisplayMode.taskPets)
            }
            .pickerStyle(.segmented).labelsHidden()
            .help("Show one companion, or up to four active task pets in your menu bar")
            if let error = content.navigationError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if tasks.isEmpty {
                emptyState
            } else {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                    TextField("Find a task…", text: $search).textFieldStyle(.plain)
                        .accessibilityLabel("Find a task")
                        .focused($searchIsFocused)
                        .onChange(of: searchIsFocused) { _, focused in
                            if focused { onBeginInteraction() }
                        }
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search")
                    }
                }
                .font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 8)
                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !attention.isEmpty { section("Needs you", tasks: attention, tint: .orange) }
                        if !working.isEmpty { section("Working", tasks: working, tint: .teal) }
                        if attention.isEmpty && working.isEmpty && search.isEmpty {
                            HStack(spacing: 12) {
                                PetPortraitView(pet: content.selectedPet, size: 44)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("All quiet for now").font(.system(size: 13, weight: .semibold))
                                    Text("Your next task will show up here.").font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 12)
                        }
                        if !recent.isEmpty {
                            DisclosureGroup(isExpanded: $showsRecent) {
                                VStack(spacing: 8) { ForEach(recent) { task in row(task) } }
                                    .padding(.top, 8)
                            } label: {
                                Text("Recent · \(recent.count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            }
                            .onChange(of: search) { _, value in if !value.isEmpty { showsRecent = true } }
                        }
                        if filtered.isEmpty {
                            Text("No tasks match “\(search)”.")
                                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 24)
                        }
                    }.padding(.bottom, 2)
                }.scrollIndicators(.automatic)
            }
            Divider()
            connectionsButton
            if showsConnections {
                ProviderConnectionsView(
                    health: content.connections,
                    installingProvider: content.installingProvider,
                    resultMessage: content.connectionMessage,
                    resultIsError: content.connectionFailed,
                    onConnect: onConnect
                )
            }
        }
        .padding(16)
        .frame(width: PetHoverPanelMetrics.width, height: height, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.1), lineWidth: 1) }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pet Bar tasks")
    }

    private func row(_ task: PetTaskPresentation) -> some View {
        let pet = content.availablePets.first { $0.id == content.assignments[task.id] } ?? content.selectedPet
        return PetTaskCardView(task: task, pet: pet, availablePets: content.availablePets,
            onOpen: { onOpenTask(task) }, onAssign: { onAssignPet(task.id, $0) }, onBeginInteraction: onBeginInteraction)
    }

    private func section(_ title: String, tasks: [PetTaskPresentation], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 5, height: 5)
                Text(title).foregroundStyle(.secondary)
                Text("\(tasks.count)").foregroundStyle(.tertiary)
            }.font(.system(size: 11, weight: .semibold))
            ForEach(tasks) { task in row(task) }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            PetPortraitView(pet: content.selectedPet, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text("Pet Bar").font(.system(size: 17, weight: .semibold))
                Text(content.statusText).font(.system(size: 11))
                    .foregroundStyle(content.needsAttention ? Color.orange : Color.secondary).lineLimit(1)
            }
            Spacer()
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape").font(.system(size: 14)).frame(width: 28, height: 28).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Pet Bar settings").accessibilityLabel("Pet Bar settings")
        }
    }

    private var connectionsButton: some View {
        Button(action: onToggleConnections) {
            HStack(spacing: 6) {
                Circle().fill(content.hasConnectionIssue ? Color.orange : content.hasReadyConnection ? .green : .secondary)
                    .frame(width: 5, height: 5)
                Text("Agents")
                Spacer()
                Text(ProviderConnectionPresentation.summary(for: content.connections))
                    .foregroundStyle(content.hasConnectionIssue ? Color.orange : Color.secondary)
                Image(systemName: showsConnections ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .semibold))
            }.font(.system(size: 11)).frame(minHeight: 20).contentShape(Rectangle())
        }.buttonStyle(.plain).help(content.petSourceText)
            .accessibilityLabel(showsConnections ? "Hide agent connections" : "Show agent connections")
            .accessibilityValue(ProviderConnectionPresentation.summary(for: content.connections))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            PetPortraitView(pet: content.selectedPet, size: 64)
            Text(!content.hasPet ? "Bring your Codex pet" : content.hasConnectionIssue ? "Let’s reconnect" : "Ready for a little company?")
                .font(.system(size: 14, weight: .semibold))
            Text(!content.hasPet
                 ? "Choose a pet in Codex, then start a task. It will appear here automatically."
                 : content.hasConnectionIssue
                 ? "Open Agents below to restore activity from your tools."
                 : "Start a task. Your pet will work alongside it and let you know when you’re needed.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 12)
    }
}

@MainActor
enum PetHoverPanelPreviewRenderer {
    static func render(to url: URL, empty: Bool = false, connections: Bool = false, dark: Bool = false) throws {
        let pets = PetLibrary(petsDirectory: CodexEnvironment.homeDirectory().appendingPathComponent("pets")).loadPetsWithDiagnostics().pets
        let selected = pets.first { $0.id == "grumble" } ?? pets.first
        let assignments = Dictionary(uniqueKeysWithValues: zip(
            ["codex:expenses-review", "claude:invoice-check", "cursor:launch-copy"],
            pets.prefix(3).map(\.id)
        ))
        let content = PetHoverPanelContent(
            petName: selected?.displayName ?? "Your pet",
            statusText: empty ? "All quiet" : "2 tasks need you",
            projects: empty ? [] : [
                PetTaskProjectPresentation(
                    id: "expenses",
                    name: "pet-bar",
                    tasks: [
                        PetTaskPresentation(
                            id: "codex:expenses-review",
                            sourceID: "expenses-review",
                            navigationSourceID: "expenses-review",
                            title: "Fix the task sidebar",
                            summary: "The keyboard check failed. Ready for you to review the focus behaviour.",
                            provider: .codex,
                            state: .failed,
                            deepLinkURL: nil,
                            projectURL: nil
                        ),
                        PetTaskPresentation(
                            id: "claude:invoice-check",
                            sourceID: "invoice-check",
                            navigationSourceID: "invoice-check",
                            title: "Add keyboard shortcuts",
                            summary: "Wiring up search and testing navigation between active tasks.",
                            provider: .claude,
                            state: .running,
                            deepLinkURL: nil,
                            projectURL: nil
                        ),
                    ]
                ),
                PetTaskProjectPresentation(
                    id: "media-lab",
                    name: "media-lab",
                    tasks: [
                        PetTaskPresentation(
                            id: "cursor:launch-copy",
                            sourceID: "launch-copy",
                            navigationSourceID: "launch-copy",
                            title: "Polish launch copy",
                            summary: "Waiting for input on the final product description.",
                            provider: .cursor,
                            state: .waiting,
                            deepLinkURL: nil,
                            projectURL: nil
                        ),
                    ]
                ),
            ],
            connections: PetProvider.allCases.map {
                ProviderIntegrationHealth(provider: $0, state: empty ? .notInstalled : .connected)
            },
            selectedPet: selected, availablePets: pets, assignments: assignments, displayMode: .taskPets
        )
        let height = content.preferredHeight + (connections ? ProviderConnectionsView.estimatedHeight(resultMessage: nil) + 38 : 0)
        let view = PetHoverPanelView(content: content, height: height, onOpenTask: { _ in }, showsConnections: connections)
            .environment(\.colorScheme, dark ? .dark : .light)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: NSSize(width: PetHoverPanelMetrics.width, height: height))
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw PetHoverPanelPreviewError.renderFailed
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw PetHoverPanelPreviewError.renderFailed
        }
        try pngData.write(to: url, options: .atomic)
    }
}

private enum PetHoverPanelPreviewError: Error {
    case renderFailed
}

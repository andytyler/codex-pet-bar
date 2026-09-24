import AppKit
import CodexPetBarCore
import SwiftUI

private enum PetHoverPanelMetrics {
    static let width: CGFloat = 360
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

    private lazy var panel: NSPanel = {
        let panel = PetTaskPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
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
    }

    func attach(
        to statusButton: NSStatusBarButton,
        contentProvider: @escaping ContentProvider,
        onOpenTask: @escaping TaskHandler
    ) {
        self.statusButton = statusButton
        self.contentProvider = contentProvider
        self.taskHandler = onOpenTask

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
        panel.orderFrontRegardless()
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
        guard !isPointerOverStatusItem, !isPointerOverPanel else {
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
        let panelHeight = min(content.preferredHeight, availableHeight)
        let rootView = PetHoverPanelView(
            content: content,
            height: panelHeight,
            onOpenTask: { [weak self] task in
                self?.dismiss()
                self?.taskHandler?(task)
            }
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
        guard panel.isVisible else {
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
                    pointerOwnsSurface: self.isPointerOverStatusItem || self.isPointerOverPanel
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header

            if content.projects.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(content.projects) { project in
                            PetTaskProjectView(project: project, onOpenTask: onOpenTask)
                        }
                    }
                    .padding(.bottom, 1)
                }
                .scrollIndicators(.automatic)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: PetHoverPanelMetrics.width, height: height, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(content.petName) tasks")
    }

    private var header: some View {
        HStack(spacing: 5) {
            Text(content.petName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text("· \(content.statusText)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !content.activeProviders.isEmpty {
                HStack(spacing: 3) {
                    ForEach(content.activeProviders, id: \.self) { provider in
                        PetProviderIconView(provider: provider, artworkSize: 15)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "Active providers: \(content.activeProviders.map(\.displayName).joined(separator: ", "))"
                )
            }

            Spacer(minLength: 2)
        }
        .frame(height: 20)
    }

    private var emptyState: some View {
        VStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.body)
                .foregroundStyle(.secondary)
            Text("No recent tasks")
                .font(.caption.weight(.semibold))
            Text("Start a task in Codex, Claude Code, or Cursor and it will appear here.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 18)
        .accessibilityElement(children: .combine)
    }
}

private struct PetTaskProjectView: View {
    let project: PetTaskProjectPresentation
    let onOpenTask: (PetTaskPresentation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(project.name, systemImage: "folder")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 2)

            VStack(spacing: 0) {
                ForEach(Array(project.tasks.enumerated()), id: \.element.id) { index, task in
                    PetTaskRowView(task: task) {
                        onOpenTask(task)
                    }

                    if index < project.tasks.count - 1 {
                        Divider()
                            .padding(.leading, 27)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(project.name) project")
    }
}

private struct PetProviderIconView: View {
    let provider: PetTaskProviderPresentation
    let artworkSize: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let image = ProviderBrandImages.inAppImage(for: provider, isDark: colorScheme == .dark) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(provider == .other ? .template : .original)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: provider.systemImageName)
                    .font(.system(size: artworkSize * 0.72, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: artworkSize, height: artworkSize)
        .accessibilityHidden(true)
    }
}

private struct PetTaskRowView: View {
    let task: PetTaskPresentation
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                providerIcon

                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(task.summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                stateIndicator
            }
            .padding(.horizontal, 4)
            .frame(height: 38)
            .background(
                Color.primary.opacity(isHovered || isFocused ? 0.065 : 0),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.75), lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .onHover { isHovered in
            self.isHovered = isHovered
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: isHovered)
        .help(task.summary)
        .accessibilityLabel("\(task.title), \(task.provider.displayName), \(task.state.displayName)")
        .accessibilityValue(task.summary)
        .accessibilityHint(task.accessibilityOpenHint)
    }

    private var providerIcon: some View {
        PetProviderIconView(provider: task.provider, artworkSize: 19)
            .frame(width: 20, height: 20)
    }

    private var stateIndicator: some View {
        Image(systemName: task.state.systemImageName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(stateForegroundColor)
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
    }

    private var stateForegroundColor: Color {
        switch task.state {
        case .running:
            .blue
        case .waiting:
            .orange
        case .completed:
            .green
        case .failed:
            .red
        case .recent:
            .secondary
        }
    }

}

/// Deterministic, app-only render used by visual QA without capturing unrelated
/// desktop content. It is inactive during normal launches.
@MainActor
enum PetHoverPanelPreviewRenderer {
    static func render(to url: URL) throws {
        let content = PetHoverPanelContent(
            petName: "Grumble",
            statusText: "3 active tasks",
            projects: [
                PetTaskProjectPresentation(
                    id: "expenses",
                    name: "expenses",
                    tasks: [
                        PetTaskPresentation(
                            id: "codex:expenses-review",
                            sourceID: "expenses-review",
                            navigationSourceID: "expenses-review",
                            title: "Update the expense review",
                            summary: "Updated the Oneder evidence; the unpaid item is still clearly flagged.",
                            provider: .codex,
                            state: .failed,
                            deepLinkURL: nil,
                            projectURL: nil
                        ),
                        PetTaskPresentation(
                            id: "claude:invoice-check",
                            sourceID: "invoice-check",
                            navigationSourceID: "invoice-check",
                            title: "Check outstanding invoices",
                            summary: "Reviewing receipts and matching the remaining supplier totals.",
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
            ]
        )
        let height = content.preferredHeight
        let view = PetHoverPanelView(content: content, height: height, onOpenTask: { _ in })
            .environment(\.colorScheme, .light)
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

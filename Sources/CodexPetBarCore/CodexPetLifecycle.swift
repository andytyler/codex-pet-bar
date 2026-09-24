import Foundation

/// Shared lifecycle semantics for menu-bar activity and hover task summaries.
///
/// Hook payloads are retained as an append-only history. This reducer interprets
/// that history instead of trusting the latest normalized `event` string in
/// isolation, which also lets newer releases repair older records immediately.
enum CodexPetLifecycle {
    static let toolCompletionDiscoveryGrace: TimeInterval = 30
    static let sessionStartGrace: TimeInterval = 90
    static let hookOnlyProviderRunningLease: TimeInterval = 30 * 60

    enum RunningEvidence: Equatable, Sendable {
        case established
        case toolCompletionDiscovery
    }

    enum Phase: Equatable, Sendable {
        case listening
        case running(RunningEvidence)
        case reviewing
        case failed
        case completed
    }

    struct State: Equatable, Sendable {
        let event: CodexPetEvent
        let phase: Phase
        let currentTurnID: String?
        let turnStartedAt: TimeInterval?

        init(event: CodexPetEvent, phase: Phase, currentTurnID: String? = nil, turnStartedAt: TimeInterval? = nil) {
            self.event = event
            self.phase = phase
            self.currentTurnID = currentTurnID
            self.turnStartedAt = turnStartedAt
        }

        var activity: CodexActivity {
            switch phase {
            case .listening:
                .listening
            case .running:
                .running
            case .reviewing:
                .reviewing
            case .failed:
                .failed
            case .completed:
                .idle
            }
        }

        func isCurrent(
            at timestamp: TimeInterval,
            activeWindow: TimeInterval,
            attentionWindow: TimeInterval,
            terminalWindow: TimeInterval
        ) -> Bool {
            let age = max(0, timestamp - event.timestamp)
            let window: TimeInterval
            switch phase {
            case .listening:
                window = min(max(0, activeWindow), sessionStartGrace)
            case .running(.established):
                let requestedWindow = max(0, activeWindow)
                switch event.provider {
                case .codex:
                    // Codex has rollout reconciliation as an additional
                    // liveness signal, so preserve its configured window.
                    window = requestedWindow
                case .claude, .cursor:
                    // Hook-only providers can miss a terminal callback when
                    // their host exits. Bound stale running flags without
                    // changing permission or failure attention retention.
                    window = min(requestedWindow, hookOnlyProviderRunningLease)
                }
            case .running(.toolCompletionDiscovery):
                window = min(max(0, activeWindow), toolCompletionDiscoveryGrace)
            case .reviewing, .failed:
                window = max(0, attentionWindow)
            case .completed:
                window = max(0, terminalWindow)
            }
            return age <= window
        }
    }

    static func reduce(
        events: [CodexPetEvent],
        activeWindow: TimeInterval,
        attentionWindow: TimeInterval,
        now: TimeInterval? = nil
    ) -> State? {
        var history = reduceHistory(events: events, activeWindow: activeWindow, attentionWindow: attentionWindow)
        if let now {
            history.pendingPermissions.removeAll { now - $0.timestamp > max(0, attentionWindow) }
        }
        guard let state = history.visibleState else { return nil }
        return State(event: state.event, phase: state.phase, currentTurnID: history.currentTurnID,
            turnStartedAt: history.turnStartedAt)
    }

    static func checkpoint(
        events: [CodexPetEvent], activeWindow: TimeInterval,
        attentionWindow: TimeInterval, retentionCutoff: TimeInterval, now: TimeInterval
    ) -> CodexPetEvent? {
        var history = reduceHistory(events: events, activeWindow: activeWindow, attentionWindow: attentionWindow)
        history.pendingPermissions.removeAll { now - $0.timestamp > max(0, attentionWindow) }
        guard let state = history.visibleState else { return nil }
        if events.count == 1, events[0].lifecycleCheckpoint == nil { return state.event }
        return state.event.withCheckpoint(CodexPetLifecycleCheckpoint(
            phase: phaseName(state.phase), currentTurnID: history.currentTurnID,
            completedTurnID: history.completedTurnID,
            completedTurns: history.completedTurns.filter { $0.value >= retentionCutoff },
            pendingPermissions: history.pendingPermissions.sorted { permissionKey($0) < permissionKey($1) }
                .map { $0.withCheckpoint(nil) },
            workPhase: history.state.map { phaseName($0.phase) },
            workEvents: history.state.map { [$0.event.withCheckpoint(nil)] } ?? [],
            summaryEvents: events.flatMap { [$0] + ($0.lifecycleCheckpoint?.summaryEvents ?? []) }
                .filter { !($0.assistantSummary?.isEmpty ?? true) }
                .sorted { $0.timestamp > $1.timestamp }.prefix(1).map { $0.withCheckpoint(nil) },
            reducedThrough: events.map { $0.lifecycleCheckpoint?.reducedThrough ?? $0.timestamp }.max(),
            turnStartedAt: history.turnStartedAt
        ), workspaceOverride: events.sorted { $0.timestamp < $1.timestamp }
            .first { !($0.workspace?.isEmpty ?? true) }?.workspace)
    }

    private struct History {
        var state: State?
        var currentTurnID: String?
        var turnStartedAt: TimeInterval?
        var completedTurnID: String?
        var completedTurns: [String: TimeInterval] = [:]
        var pendingPermissions: [CodexPetEvent] = []
        var visibleState: State? {
            if let pending = pendingPermissions.max(by: { $0.timestamp < $1.timestamp }) {
                return State(event: pending, phase: .reviewing)
            }
            return state
        }
    }

    private static func reduceHistory(
        events: [CodexPetEvent], activeWindow: TimeInterval, attentionWindow: TimeInterval
    ) -> History {
        let orderedEvents = events.enumerated().sorted { left, right in
            let leftTimestamp = left.element.lifecycleCheckpoint?.reducedThrough ?? left.element.timestamp
            let rightTimestamp = right.element.lifecycleCheckpoint?.reducedThrough ?? right.element.timestamp
            if leftTimestamp != rightTimestamp {
                return leftTimestamp < rightTimestamp
            }
            return left.offset < right.offset
        }.map(\.element)
        var history = History()
        for event in orderedEvents {
            if let checkpoint = event.lifecycleCheckpoint, let phase = phase(named: checkpoint.phase) {
                if let workEvent = checkpoint.workEvents?.first, let workName = checkpoint.workPhase,
                    let workPhase = self.phase(named: workName) {
                    history.state = State(event: workEvent, phase: workPhase)
                } else {
                    history.state = State(event: event, phase: phase)
                }
                history.currentTurnID = checkpoint.currentTurnID
                history.turnStartedAt = checkpoint.turnStartedAt
                history.completedTurnID = checkpoint.completedTurnID
                history.completedTurns = checkpoint.completedTurns
                history.pendingPermissions = checkpoint.pendingPermissions
                continue
            }
            guard !isIgnored(event), isStateBearing(event) else { continue }
            let eventTurnID = nonEmpty(event.turnID)
            if let eventTurnID, history.completedTurns[eventTurnID] != nil {
                let continuation = isTerminal(event) && history.state?.phase == .completed
                    && history.completedTurnID == eventTurnID
                if !continuation { continue }
            }
            if history.state?.phase == .completed, !isTerminal(event) {
                guard beginsNewTurn(event, after: history.completedTurnID) else { continue }
                history.state = nil
                history.currentTurnID = eventTurnID
                history.turnStartedAt = nil
                history.completedTurnID = nil
                history.pendingPermissions.removeAll()
            }
            if isTerminal(event) {
                history.currentTurnID = eventTurnID ?? history.currentTurnID
                history.completedTurnID = history.currentTurnID
                if let turnID = history.completedTurnID { history.completedTurns[turnID] = event.timestamp }
                history.pendingPermissions.removeAll()
                history.state = State(event: event, phase: .completed)
                continue
            }
            if event.kind == "session_started" || event.kind == "prompt_submitted" {
                history.pendingPermissions.removeAll()
                history.currentTurnID = eventTurnID
                history.turnStartedAt = event.timestamp
            } else if let eventTurnID {
                if let previousTurnID = history.currentTurnID, previousTurnID != eventTurnID {
                    history.pendingPermissions.removeAll()
                }
                history.currentTurnID = eventTurnID
            }
            history.pendingPermissions.removeAll { event.timestamp - $0.timestamp > max(0, attentionWindow) }
            switch event.kind {
            case "session_started":
                history.state = State(event: event, phase: .listening)
            case "prompt_submitted", "tool_started", "edit_started":
                history.state = State(event: event, phase: .running(.established))
            case "permission_requested":
                history.pendingPermissions.removeAll { permissionKey($0) == permissionKey(event) }
                history.pendingPermissions.append(event.withCheckpoint(nil))
                if history.state == nil { history.state = State(event: event, phase: .reviewing) }
            case "tool_failed", "tool_succeeded":
                let resolvedPermission = history.pendingPermissions.contains { resolves(event, permission: $0) }
                history.pendingPermissions.removeAll { resolves(event, permission: $0) }
                if event.kind == "tool_failed" {
                    history.state = State(event: event, phase: .failed)
                } else if resolvedPermission {
                    history.state = State(event: event, phase: .running(.established))
                } else {
                    history.state = stateAfterToolCompletion(event, previousState: history.state,
                        activeWindow: activeWindow, attentionWindow: attentionWindow)
                }
            default:
                break
            }
            // Work evidence continues to advance behind unresolved attention;
            // visibleState keeps the permission's age without discarding work.
        }
        return history
    }

    private static func permissionKey(_ event: CodexPetEvent) -> String {
        if let id = nonEmpty(event.permissionRequestID) { return "request:" + id }
        if let id = nonEmpty(event.toolUseID) { return "tool:" + id }
        // Without correlation, only an explicit lifecycle boundary or matching
        // elicitation result clears attention. Tool names are not invocation IDs.
        return "uncorrelated:" + (event.hookEventName ?? "") + ":" + (event.toolName ?? "")
    }

    private static func resolves(_ event: CodexPetEvent, permission: CodexPetEvent) -> Bool {
        if let id = nonEmpty(permission.permissionRequestID), id == nonEmpty(event.permissionRequestID) { return true }
        if let id = nonEmpty(permission.toolUseID), id == nonEmpty(event.toolUseID) { return true }
        return event.hookEventName == "ElicitationResult" && permission.hookEventName == "Elicitation"
            && permission.permissionRequestID == nil && permission.toolUseID == nil
    }

    private static func phaseName(_ phase: Phase) -> String {
        switch phase {
        case .listening: "listening"
        case .running(.established): "running_established"
        case .running(.toolCompletionDiscovery): "running_discovery"
        case .reviewing: "reviewing"
        case .failed: "failed"
        case .completed: "completed"
        }
    }

    private static func phase(named name: String) -> Phase? {
        switch name {
        case "listening": .listening
        case "running_established": .running(.established)
        case "running_discovery": .running(.toolCompletionDiscovery)
        case "reviewing": .reviewing
        case "failed": .failed
        case "completed": .completed
        default: nil
        }
    }

    static func isStateBearing(_ event: CodexPetEvent) -> Bool {
        guard !isIgnored(event) else {
            return false
        }
        if isTerminal(event) {
            return true
        }
        switch event.kind {
        case "session_started", "prompt_submitted", "tool_started", "edit_started",
             "tool_succeeded", "permission_requested", "tool_failed", "stopped":
            return true
        default:
            return false
        }
    }

    static func isTerminal(_ event: CodexPetEvent) -> Bool {
        if event.kind == "stopped" {
            return true
        }
        if event.provider == .claude, event.status == "background_active" {
            return true
        }

        switch (event.provider, event.hookEventName) {
        case (.codex, "Stop"), (.codex, "SessionEnd"), (.codex, "SubagentStop"),
             (.claude, "Stop"), (.claude, "SessionEnd"), (.claude, "SubagentStop"),
             (.cursor, "afterAgentResponse"), (.cursor, "stop"), (.cursor, "sessionEnd"):
            return true
        default:
            return false
        }
    }

    private static func isIgnored(_ event: CodexPetEvent) -> Bool {
        if event.provider == .claude, event.hookEventName == "Notification" {
            // New hook records persist Claude's notification_type in status.
            // Only the two actionable notification types represent attention.
            // Historical untagged records are intentionally ignored: most are
            // idle prompts, and real permission requests also have a dedicated
            // PermissionRequest hook.
            switch normalized(event.status) {
            case "permission_prompt", "elicitation_dialog":
                return event.kind != "permission_requested"
            default:
                return true
            }
        }
        if
            event.provider == .cursor,
            event.hookEventName == "subagentStart" || event.hookEventName == "subagentStop"
        {
            // Cursor's subagent hook identifier is opaque and does not match
            // the child Composer session subsequently used by tool hooks.
            // Counting both creates two flags for the same logical child.
            return true
        }
        return false
    }

    private static func beginsNewTurn(_ event: CodexPetEvent, after completedTurnID: String?) -> Bool {
        if event.kind == "session_started" {
            return true
        }

        let eventTurnID = nonEmpty(event.turnID)
        if event.kind == "prompt_submitted" {
            guard let completedTurnID, let eventTurnID else {
                return true
            }
            return eventTurnID != completedTurnID
        }

        guard let completedTurnID, let eventTurnID else {
            return false
        }
        return eventTurnID != completedTurnID
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func normalized(_ value: String?) -> String? {
        nonEmpty(value?.trimmingCharacters(in: .whitespacesAndNewlines))?.lowercased()
    }

    private static func stateAfterToolCompletion(
        _ event: CodexPetEvent,
        previousState: State?,
        activeWindow: TimeInterval,
        attentionWindow: TimeInterval
    ) -> State? {
        guard let previousState else {
            return State(event: event, phase: .running(.toolCompletionDiscovery))
        }
        guard previousState.phase != .completed else {
            // A lagging concurrent PostToolUse must never resurrect a turn
            // after its terminal hook has already arrived.
            return previousState
        }
        guard previousState.isCurrent(
            at: event.timestamp,
            activeWindow: activeWindow,
            attentionWindow: attentionWindow,
            terminalWindow: 0
        ) else {
            return State(event: event, phase: .running(.toolCompletionDiscovery))
        }

        let evidence: RunningEvidence = previousState.phase == .running(.toolCompletionDiscovery)
            ? .toolCompletionDiscovery
            : .established
        return State(event: event, phase: .running(evidence))
    }
}

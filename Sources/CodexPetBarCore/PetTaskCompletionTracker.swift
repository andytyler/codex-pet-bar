import Foundation

/// Detects new successful top-level task finishes. Expiry and disappearing
/// activity never count as completion. Retained startup history is silent.
public struct PetTaskCompletionTracker: Sendable {
    private struct ScopeKey: Hashable, Sendable {
        let provider: PetProvider
        let sessionID: String
    }

    private struct TerminalKey: Hashable, Sendable {
        let scope: ScopeKey
        let identity: String
    }

    private struct ScanObservation: Equatable, Sendable {
        let state: CodexRunningThreadLog.State
        let marker: CodexRunningThreadLog.Marker?
    }

    private struct Run: Sendable {
        var turnID: String?
        var armed = false
        var closed = false
        var latestWorkTimestamp = -Double.infinity
        var terminalTimestamp = -Double.infinity
        var scanObservation: ScanObservation?
        var lastAccess: UInt64 = 0
    }

    private let startedAt: TimeInterval
    private var hasConsumedScan = false
    private var runs: [ScopeKey: Run] = [:]
    private var seenTerminals = Set<TerminalKey>()
    private var terminalOrder: [TerminalKey] = []
    private var accessCounter: UInt64 = 0
    private static let retentionLimit = 512

    public init(startedAt: Date = Date()) {
        self.startedAt = startedAt.timeIntervalSince1970
    }

    /// Input may include retained history: its timestamps establish state but
    /// cannot announce completion before this tracker started.
    public mutating func consumeHookEvents(_ events: [CodexPetEvent], now: Date) -> Bool {
        var finished = Set<ScopeKey>()
        let ordered = events.enumerated().sorted {
            if $0.element.timestamp != $1.element.timestamp {
                return $0.element.timestamp < $1.element.timestamp
            }
            return $0.offset < $1.offset
        }
        for (_, event) in ordered {
            guard
                event.timestamp.isFinite,
                event.timestamp <= now.timeIntervalSince1970 + 5,
                event.parentSessionID == nil,
                let sessionID = Self.nonEmpty(event.sessionID),
                !Self.isChildHook(event.hookEventName),
                // A response callback is not Cursor's final agent-stop result.
                event.hookEventName != "afterAgentResponse"
            else { continue }

            let key = ScopeKey(provider: event.provider, sessionID: sessionID)
            let turnID = Self.nonEmpty(event.turnID)
            if Self.isTerminalHook(event) {
                let successful = Self.isSuccessfulHook(event)
                if close(
                    key, turnID: turnID,
                    identity: turnID.map { "turn:\($0)" } ?? "hook:\(event.timestamp)",
                    timestamp: event.timestamp, successful: successful,
                    allowEmission: true, allowUnobservedTurn: false, now: now
                ) {
                    finished.insert(key)
                } else if Self.isExplicitFailure(event), turnID == nil || runs[key]?.turnID == turnID {
                    finished.remove(key)
                }
                continue
            }

            // PostToolUse, including a successful tool result, cannot finish or
            // resurrect a task. Ordinary notifications are not new work either.
            guard ["session_started", "prompt_submitted", "tool_started", "edit_started"].contains(event.kind)
            else { continue }
            let boundary = event.kind == "session_started" || event.kind == "prompt_submitted"
            if observeWork(
                key, turnID: turnID, timestamp: event.timestamp,
                isBoundary: boundary, arm: event.kind != "session_started"
            ) {
                finished.remove(key)
            }
        }
        return !finished.isEmpty
    }

    /// The first scan is a silent baseline. Subsequent explicit success records
    /// can announce completion; changing file mtime alone cannot replay one.
    public mutating func consumeScan(_ scan: CodexRunningThreadScan, now: Date) -> Bool {
        let isBaseline = !hasConsumedScan
        hasConsumedScan = true
        var finished = Set<ScopeKey>()
        let scopes = scan.runningScopes.map { ($0, CodexRunningThreadLog.State.running) }
            + scan.completedScopes.map { ($0, CodexRunningThreadLog.State.completed) }
        for (scope, state) in scopes {
            guard scope.parentSessionID == nil, !scope.sessionID.isEmpty else { continue }
            let key = ScopeKey(provider: .codex, sessionID: scope.sessionID)
            let marker = scope.marker
            guard marker == nil || marker?.state == state else { continue }
            if let timestamp = marker?.timestamp, timestamp > now.timeIntervalSince1970 + 5 { continue }
            let observation = ScanObservation(state: state, marker: scope.marker)
            var run = runs[key] ?? Run()
            guard observation != run.scanObservation else { continue }
            run.scanObservation = observation
            store(run, for: key)

            if state == .running {
                if observeWork(
                    key, turnID: marker?.turnID,
                    timestamp: marker?.timestamp ?? now.timeIntervalSince1970,
                    isBoundary: true, arm: true
                ) {
                    finished.remove(key)
                }
            } else {
                // Legacy scopes lack success evidence. They remain valid for
                // activity reconciliation, but cannot generate a Done cue.
                let success = marker?.completionOutcome == .success
                if close(
                    key, turnID: marker?.turnID, identity: marker?.terminalIdentity,
                    timestamp: marker?.timestamp, successful: success,
                    allowEmission: !isBaseline, allowUnobservedTurn: true, now: now
                ) {
                    finished.insert(key)
                }
            }
        }
        return !finished.isEmpty
    }

    /// Returns true only when this observation establishes current work.
    private mutating func observeWork(
        _ key: ScopeKey, turnID: String?, timestamp: TimeInterval,
        isBoundary: Bool, arm: Bool
    ) -> Bool {
        var run = runs[key] ?? Run()
        if let turnID, seenTerminals.contains(TerminalKey(scope: key, identity: "turn:\(turnID)")) {
            return false
        }
        guard timestamp >= run.latestWorkTimestamp, timestamp > run.terminalTimestamp else { return false }
        let differentTurn = turnID != nil && turnID != run.turnID
        guard !run.closed || isBoundary || differentTurn else { return false }
        if isBoundary || differentTurn { run.turnID = turnID }
        else if let turnID { run.turnID = turnID }
        run.armed = arm || (!run.closed && run.armed)
        run.closed = false
        run.latestWorkTimestamp = timestamp
        store(run, for: key)
        return true
    }

    private mutating func close(
        _ key: ScopeKey, turnID: String?, identity: String?,
        timestamp: TimeInterval?, successful: Bool, allowEmission: Bool,
        allowUnobservedTurn: Bool, now: Date
    ) -> Bool {
        var run = runs[key] ?? Run()
        let isNewScannedTurn = allowUnobservedTurn && run.closed
            && turnID != nil && run.turnID != nil && turnID != run.turnID
            && (timestamp.map { $0 > run.terminalTimestamp } ?? false)
        // An old turn may arrive late after the next prompt has already begun.
        // A rollout carries actual event time, so a distinct later terminal can
        // also reveal a short turn that began and ended between scanner polls.
        if let turnID, let currentTurn = run.turnID, turnID != currentTurn, !isNewScannedTurn {
            remember(TerminalKey(scope: key, identity: "turn:\(turnID)"))
            return false
        }
        if let timestamp, timestamp < run.latestWorkTimestamp { return false }
        let effectiveTurnID = turnID ?? run.turnID
        let effectiveIdentity = effectiveTurnID.map { "turn:\($0)" } ?? identity
        let terminalKey = effectiveIdentity.map { TerminalKey(scope: key, identity: $0) }
        let alreadySeen = terminalKey.map { seenTerminals.contains($0) } ?? false
        let fresh: Bool
        if let timestamp {
            fresh = timestamp >= startedAt && timestamp <= now.timeIntervalSince1970 + 5
        } else {
            // Untimestamped legacy markers require a witnessed running phase;
            // their file mtime is deliberately never substituted as evidence.
            fresh = run.armed && now.timeIntervalSince1970 >= startedAt
        }
        let emit = allowEmission && successful && fresh && (!run.closed || isNewScannedTurn) && !alreadySeen
        if let terminalKey { remember(terminalKey) }
        run.turnID = effectiveTurnID
        run.armed = false
        run.closed = true
        run.terminalTimestamp = max(run.terminalTimestamp, timestamp ?? now.timeIntervalSince1970)
        store(run, for: key)
        return emit
    }

    private mutating func store(_ run: Run, for key: ScopeKey) {
        accessCounter &+= 1
        var value = run
        value.lastAccess = accessCounter
        runs[key] = value
        if runs.count > Self.retentionLimit,
           let oldest = runs.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key {
            runs.removeValue(forKey: oldest)
        }
    }

    private mutating func remember(_ key: TerminalKey) {
        guard seenTerminals.insert(key).inserted else { return }
        terminalOrder.append(key)
        if terminalOrder.count > Self.retentionLimit {
            seenTerminals.remove(terminalOrder.removeFirst())
        }
    }

    private static func isChildHook(_ hook: String?) -> Bool {
        ["SubagentStart", "SubagentStop", "subagentStart", "subagentStop"].contains(hook ?? "")
    }

    private static func isTerminalHook(_ event: CodexPetEvent) -> Bool {
        if event.kind == "stopped" { return true }
        return ["Stop", "StopFailure", "SessionEnd", "stop", "sessionEnd"].contains(event.hookEventName ?? "")
    }

    private static func isSuccessfulHook(_ event: CodexPetEvent) -> Bool {
        guard event.kind == "stopped" else { return false }
        let status = event.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch (event.provider, event.hookEventName) {
        case (.codex, "Stop"), (.claude, "Stop"):
            return ["", "completed", "complete", "success", "succeeded"].contains(status)
        case (.cursor, "stop"):
            return ["completed", "complete", "success", "succeeded"].contains(status)
        default:
            return false
        }
    }

    private static func isExplicitFailure(_ event: CodexPetEvent) -> Bool {
        if event.hookEventName == "StopFailure" { return true }
        let status = event.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return ["aborted", "cancelled", "canceled", "interrupted", "error", "failed", "failure"].contains(status)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        value.flatMap { $0.isEmpty ? nil : $0 }
    }
}

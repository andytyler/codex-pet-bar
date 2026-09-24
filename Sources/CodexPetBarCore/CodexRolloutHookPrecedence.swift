import Foundation

/// Keeps a cached rollout scan from overriding newer lifecycle hooks while
/// the next asynchronous scan is still pending.
public enum CodexRolloutHookPrecedence {
    public static func filter(
        scopes: [CodexRolloutActivityScope],
        events: [CodexPetEvent]
    ) -> [CodexRolloutActivityScope] {
        let eventsBySession = Dictionary(grouping: events.filter {
            $0.provider == .codex && $0.timestamp.isFinite
                && $0.sessionID?.isEmpty == false && CodexPetLifecycle.isStateBearing($0)
        }, by: { $0.sessionID! })

        return scopes.filter { scope in
            // File writes after a terminal record do not make that record newer.
            let timestamp = scope.marker?.timestamp ?? scope.modificationDate.timeIntervalSince1970
            if let hooks = eventsBySession[scope.sessionID] {
                if let marker = scope.marker {
                    let baseline = CodexPetEvent(
                        kind: marker.state == .completed ? "stopped" : "prompt_submitted",
                        timestamp: timestamp,
                        provider: .codex,
                        sessionID: scope.sessionID,
                        parentSessionID: scope.parentSessionID,
                        turnID: marker.turnID,
                        hookEventName: "rollout_precedence_baseline"
                    )
                    // Reuse the same terminal/turn rules as activity snapshots.
                    // In particular, late tool results cannot reopen a completed turn.
                    if let state = lifecycle(hooks + [baseline]),
                       state.event != baseline, state.event.timestamp > timestamp {
                        return false
                    }
                } else if let state = lifecycle(hooks), state.event.timestamp > timestamp {
                    return false
                }
            }

            // A parent's stop ends older child scan activity, but its ordinary
            // work does not supersede children and a newer child run survives.
            if let parentID = scope.parentSessionID,
               let parentHooks = eventsBySession[parentID],
               let parent = lifecycle(parentHooks), parent.phase == .completed,
               parent.event.hookEventName != "SubagentStop",
               parent.event.timestamp > timestamp {
                return false
            }
            return true
        }
    }

    private static func lifecycle(_ events: [CodexPetEvent]) -> CodexPetLifecycle.State? {
        CodexPetLifecycle.reduce(
            events: events,
            activeWindow: .greatestFiniteMagnitude,
            attentionWindow: .greatestFiniteMagnitude
        )
    }
}

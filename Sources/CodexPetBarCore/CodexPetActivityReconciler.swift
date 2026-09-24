import Foundation

/// Purely reconciles rollout-verified Codex threads with hook-derived activity.
public enum CodexPetActivityReconciler {
    public static func merging(
        snapshot: CodexPetActivitySnapshot,
        runningCodexThreadIDs: [String],
        completedCodexThreadIDs: Set<String> = []
    ) -> CodexPetActivitySnapshot {
        merging(
            snapshot: snapshot,
            runningCodexScopes: runningCodexThreadIDs.map { CodexRolloutActivityScope(sessionID: $0) },
            completedCodexScopes: completedCodexThreadIDs.map { CodexRolloutActivityScope(sessionID: $0) }
        )
    }

    public static func merging(
        snapshot: CodexPetActivitySnapshot,
        runningCodexScopes: [CodexRolloutActivityScope],
        completedCodexScopes: [CodexRolloutActivityScope] = []
    ) -> CodexPetActivitySnapshot {
        let verifiedScopes = newestScopesBySessionID(runningCodexScopes)
        let verifiedThreadIDs = Set(verifiedScopes.keys)
        let completedScopes = newestScopesBySessionID(completedCodexScopes)
        let verifiedCompletedThreadIDs = Set(completedScopes.keys)
            .subtracting(verifiedThreadIDs)
        let completedScopeIdentities = Set(verifiedCompletedThreadIDs.map(codexSessionScopedIdentity))

        var scopesByIdentity: [ScopeKey: CodexPetActiveScope] = [:]
        var removedCodexSessionIDs = Set<String>()
        for scope in snapshot.activeScopes {
            let parentCompleted = scope.parentSessionID.flatMap { completedScopes[$0] }
                .map { completion($0, closes: scope) && verifiedCompletedThreadIDs.contains($0.sessionID) } ?? false
            let ownCompleted = scope.sessionID.flatMap { completedScopes[$0] }
                .map { completion($0, closes: scope) && verifiedCompletedThreadIDs.contains($0.sessionID) }
                ?? completedScopeIdentities.contains(scope.scopedIdentity)
            let childIsVerifiedRunning = scope.sessionID.map(verifiedThreadIDs.contains) ?? false
            if
                scope.provider == .codex,
                ownCompleted || (parentCompleted && !childIsVerifiedRunning)
            {
                if let sessionID = scope.sessionID, !sessionID.isEmpty {
                    removedCodexSessionIDs.insert(sessionID)
                }
                continue
            }
            let key = ScopeKey(scope: scope)
            if
                let existing = scopesByIdentity[key],
                priority(for: existing.activity) >= priority(for: scope.activity)
            {
                continue
            }
            scopesByIdentity[key] = scope
        }

        for verifiedScope in verifiedScopes.values {
            let threadID = verifiedScope.sessionID
            let scope = CodexPetActiveScope(
                provider: .codex,
                scopedIdentity: codexSessionScopedIdentity(threadID: threadID),
                activity: .running,
                sessionID: threadID,
                parentSessionID: verifiedScope.parentSessionID,
                timestamp: verifiedScope.marker?.timestamp ?? (verifiedScope.modificationDate == .distantPast
                    ? nil : verifiedScope.modificationDate.timeIntervalSince1970),
                workspace: verifiedScope.workspace,
                turnID: verifiedScope.marker?.turnID
            )
            let key = ScopeKey(scope: scope)
            if let existing = scopesByIdentity[key] {
                if existing.sessionID == nil || (existing.parentSessionID == nil && verifiedScope.parentSessionID != nil)
                    || (existing.workspace == nil && verifiedScope.workspace != nil) {
                    scopesByIdentity[key] = CodexPetActiveScope(
                        provider: existing.provider,
                        scopedIdentity: existing.scopedIdentity,
                        activity: existing.activity,
                        sessionID: existing.sessionID ?? threadID,
                        parentSessionID: existing.parentSessionID ?? verifiedScope.parentSessionID,
                        timestamp: existing.timestamp,
                        workspace: existing.workspace ?? verifiedScope.workspace,
                        turnID: existing.turnID,
                        turnStartedAt: existing.turnStartedAt
                    )
                }
                continue
            }
            scopesByIdentity[key] = scope
        }

        let activeScopes = scopesByIdentity.values.sorted(by: scopePrecedes)
        var activeSessionIDs = snapshot.activeSessionIDs
        activeSessionIDs.subtract(verifiedCompletedThreadIDs)
        activeSessionIDs.subtract(removedCodexSessionIDs)
        activeSessionIDs.formUnion(verifiedThreadIDs)
        activeSessionIDs.formUnion(activeScopes.compactMap { scope in
            scope.sessionID.map { scope.provider == .codex ? $0 : "\(scope.provider.rawValue):\($0)" }
        })

        let activities = activeScopes.map(\.activity)
        return CodexPetActivitySnapshot(
            activity: activities.max { priority(for: $0) < priority(for: $1) },
            activeSessionIDs: activeSessionIDs,
            activeScopeCount: activeScopes.count,
            activeScopes: activeScopes
        )
    }

    private static func completion(_ completion: CodexRolloutActivityScope, closes scope: CodexPetActiveScope) -> Bool {
        guard let hookTimestamp = scope.timestamp else { return true }
        let completionTimestamp = completion.marker?.timestamp
            ?? (completion.modificationDate == .distantPast ? nil : completion.modificationDate.timeIntervalSince1970)
        guard let completionTimestamp, hookTimestamp > completionTimestamp else { return true }
        guard let marker = completion.marker else {
            // Older callers expose only file timestamps, without lifecycle data.
            return false
        }
        if completion.sessionID == scope.sessionID, let completedTurn = marker.turnID, let activeTurn = scope.turnID {
            // A delayed callback is not new work merely because it arrived
            // after Stop. A distinct explicit turn is affirmative new evidence.
            return completedTurn == activeTurn
        }
        // Without comparable turn IDs, only a real prompt/session boundary
        // reopens completed work. Parent completion follows the same rule.
        return !(scope.turnStartedAt.map { $0 > completionTimestamp } ?? false)
    }

    private static func newestScopesBySessionID(
        _ scopes: [CodexRolloutActivityScope]
    ) -> [String: CodexRolloutActivityScope] {
        var result: [String: CodexRolloutActivityScope] = [:]
        for scope in scopes where !scope.sessionID.isEmpty {
            if
                let existing = result[scope.sessionID],
                existing.modificationDate >= scope.modificationDate
            {
                continue
            }
            result[scope.sessionID] = scope
        }
        return result
    }

    static func codexSessionScopedIdentity(threadID: String) -> String {
        [
            identityComponent(name: "provider", value: PetProvider.codex.rawValue),
            identityComponent(name: "workspace", value: ""),
            identityComponent(name: "session", value: threadID),
            identityComponent(name: "turn", value: ""),
        ]
        .joined(separator: "|")
    }

    private struct ScopeKey: Hashable {
        let provider: PetProvider
        let scopedIdentity: String

        init(scope: CodexPetActiveScope) {
            provider = scope.provider
            scopedIdentity = scope.scopedIdentity
        }
    }

    private static func identityComponent(name: String, value: String) -> String {
        "\(name)=\(value.utf8.count):\(value)"
    }

    private static func scopePrecedes(_ lhs: CodexPetActiveScope, _ rhs: CodexPetActiveScope) -> Bool {
        let lhsProviderOrder = providerOrder(lhs.provider)
        let rhsProviderOrder = providerOrder(rhs.provider)
        if lhsProviderOrder != rhsProviderOrder {
            return lhsProviderOrder < rhsProviderOrder
        }
        return lhs.scopedIdentity < rhs.scopedIdentity
    }

    private static func providerOrder(_ provider: PetProvider) -> Int {
        switch provider {
        case .codex:
            0
        case .claude:
            1
        case .cursor:
            2
        }
    }

    private static func priority(for activity: CodexActivity) -> Int {
        switch activity {
        case .idle:
            0
        case .listening:
            1
        case .running:
            2
        case .failed:
            3
        case .reviewing:
            4
        }
    }
}

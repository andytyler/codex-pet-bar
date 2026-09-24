/// Coordinates provider-specific pet attention presentations independently of
/// rendering and timing. Reviewing scopes keep cycling while they remain
/// active, while failed scopes are presented once per continuous appearance.
public struct PetAttentionPresentationQueue: Sendable {
    private struct PendingPresentation: Equatable, Sendable {
        let id: ScopeID
        let isRepeat: Bool
    }

    private struct ScopeID: Hashable, Sendable {
        let provider: PetProvider
        let scopedIdentity: String
        let activity: CodexActivity

        init(_ scope: CodexPetActiveScope) {
            provider = scope.provider
            scopedIdentity = scope.scopedIdentity
            activity = scope.activity
        }
    }

    private var scopesByID: [ScopeID: CodexPetActiveScope] = [:]
    private var pendingPresentations: [PendingPresentation] = []
    private var activeID: ScopeID?
    public private(set) var activePresentationIsRepeat = false
    private var presentedFailureIDs: Set<ScopeID> = []

    public init() {}

    /// The scope whose provider flag should currently be presented by the pet.
    public var activeScope: CodexPetActiveScope? {
        activeID.flatMap { scopesByID[$0] }
    }

    public var activeProvider: PetProvider? {
        activeScope?.provider
    }

    /// Reconciles the queue with the latest active-scope snapshot. The first
    /// synchronization intentionally treats preexisting attention as new so an
    /// app launch does not miss an already-waiting request.
    public mutating func synchronize(scopes: [CodexPetActiveScope]) {
        let previousIDs = Set(scopesByID.keys)
        let updatedScopes = attentionScopesByID(scopes)
        let updatedIDs = Set(updatedScopes.keys)

        scopesByID = updatedScopes
        pendingPresentations.removeAll { !updatedIDs.contains($0.id) }
        presentedFailureIDs.formIntersection(updatedIDs)

        if let activeID, !updatedIDs.contains(activeID) {
            self.activeID = nil
            activePresentationIsRepeat = false
        }

        let newIDs = updatedIDs
            .subtracting(previousIDs)
            .filter { id in
                id.activity != .failed || !presentedFailureIDs.contains(id)
            }
            .sorted(by: scopePrecedes)

        let newPresentations = newIDs.compactMap { id -> PendingPresentation? in
            guard id != activeID, !pendingPresentations.contains(where: { $0.id == id }) else {
                return nil
            }
            return PendingPresentation(id: id, isRepeat: false)
        }

        if activePresentationIsRepeat, !newPresentations.isEmpty, let activeID {
            pendingPresentations.append(PendingPresentation(id: activeID, isRepeat: true))
            self.activeID = nil
            activePresentationIsRepeat = false
        }
        pendingPresentations.insert(contentsOf: newPresentations, at: 0)

        activateNextIfNeeded()
    }

    /// Advances after the controller finishes the current zoom-and-wave cycle.
    /// A still-active review returns to the back of the queue; a failure does
    /// not return until it disappears from a later synchronization.
    public mutating func presentationDidFinish() {
        guard let finishedID = activeID else {
            activateNextIfNeeded()
            return
        }

        activeID = nil
        activePresentationIsRepeat = false

        guard scopesByID[finishedID] != nil else {
            activateNextIfNeeded()
            return
        }

        switch finishedID.activity {
        case .reviewing:
            if !pendingPresentations.contains(where: { $0.id == finishedID }) {
                pendingPresentations.append(PendingPresentation(id: finishedID, isRepeat: true))
            }
        case .failed:
            presentedFailureIDs.insert(finishedID)
        case .idle, .running, .listening:
            break
        }

        activateNextIfNeeded()
    }

    private mutating func activateNextIfNeeded() {
        guard activeID == nil else {
            return
        }

        while !pendingPresentations.isEmpty {
            let candidate = pendingPresentations.removeFirst()
            guard scopesByID[candidate.id] != nil else {
                continue
            }
            guard candidate.id.activity != .failed || !presentedFailureIDs.contains(candidate.id) else {
                continue
            }
            activeID = candidate.id
            activePresentationIsRepeat = candidate.isRepeat
            return
        }
    }

    private func attentionScopesByID(_ scopes: [CodexPetActiveScope]) -> [ScopeID: CodexPetActiveScope] {
        var result: [ScopeID: CodexPetActiveScope] = [:]
        for scope in scopes where scope.activity == .reviewing || scope.activity == .failed {
            result[ScopeID(scope)] = scope
        }
        return result
    }

    private func scopePrecedes(_ lhs: ScopeID, _ rhs: ScopeID) -> Bool {
        let lhsProviderOrder = providerOrder(lhs.provider)
        let rhsProviderOrder = providerOrder(rhs.provider)
        if lhsProviderOrder != rhsProviderOrder {
            return lhsProviderOrder < rhsProviderOrder
        }
        if lhs.scopedIdentity != rhs.scopedIdentity {
            return lhs.scopedIdentity < rhs.scopedIdentity
        }
        return activityOrder(lhs.activity) < activityOrder(rhs.activity)
    }

    private func providerOrder(_ provider: PetProvider) -> Int {
        switch provider {
        case .codex:
            0
        case .claude:
            1
        case .cursor:
            2
        }
    }

    private func activityOrder(_ activity: CodexActivity) -> Int {
        switch activity {
        case .reviewing:
            0
        case .failed:
            1
        case .idle, .running, .listening:
            2
        }
    }
}

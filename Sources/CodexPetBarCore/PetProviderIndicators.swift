extension PetMenuBarPresentation {
    /// One indicator per provider, ordered by PetProvider.allCases. The most
    /// urgent task supplies each indicator; equal urgency retains the first task.
    /// Keep the original scopes for the task count, hover list, and attention queue.
    public static func providerIndicators(for scopes: [CodexPetActiveScope]) -> [CodexPetActiveScope] {
        func priority(_ activity: CodexActivity) -> Int {
            switch activity {
            case .failed: 4
            case .reviewing: 3
            case .running: 2
            case .listening: 1
            case .idle: 0
            }
        }

        var representatives: [PetProvider: CodexPetActiveScope] = [:]
        for scope in scopes {
            if let current = representatives[scope.provider],
               priority(current.activity) >= priority(scope.activity) {
                continue
            }
            representatives[scope.provider] = scope
        }
        return PetProvider.allCases.compactMap { representatives[$0] }
    }
}

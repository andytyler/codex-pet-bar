/// A concise title derived from the same active scopes as the menu-bar flags.
/// Historical cards and a brief completion animation must not hide another
/// task's unresolved request for attention.
public enum PetTaskOverview {
    public static func title(
        scopes: [CodexPetActiveScope],
        showsCompletion: Bool,
        currentActivity: CodexActivity
    ) -> String {
        let attentionCount = scopes.filter { $0.activity == .reviewing || $0.activity == .failed }.count
        if attentionCount > 0 {
            return attentionCount == 1 ? "1 task needs you" : "\(attentionCount) tasks need you"
        }

        let runningCount = scopes.filter { $0.activity == .running }.count
        let listeningCount = scopes.filter { $0.activity == .listening }.count
        if runningCount > 0 {
            if listeningCount > 0 {
                return "\(runningCount + listeningCount) active tasks"
            }
            return runningCount == 1 ? "1 task working" : "\(runningCount) tasks working"
        }
        if listeningCount > 0 {
            return "Listening"
        }

        // Manual/preview activity may have no task identity. Preserve its
        // attention signal even when a completion animation is still visible.
        if currentActivity == .reviewing || currentActivity == .failed {
            return "Needs your attention"
        }
        if showsCompletion {
            return "All done"
        }

        switch currentActivity {
        case .idle: return "All quiet"
        case .running: return "Working"
        case .listening: return "Listening"
        case .reviewing, .failed: return "Needs your attention"
        }
    }
}

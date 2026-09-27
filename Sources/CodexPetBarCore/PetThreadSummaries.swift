import Foundation

/// A presentation-only view of the work a user can navigate to. Raw run
/// summaries remain independent inputs to activity and lifecycle tracking.
public enum PetThreadSummaries {
    public static func consolidated(_ tasks: [PetTaskSummary]) -> [PetTaskSummary] {
        let versionsByID = Dictionary(grouping: tasks, by: \.id)
        // A newer version of the same run resolves its older state before
        // children contribute activity to their navigable parent.
        let unique = versionsByID.values.compactMap { $0.sorted(by: newestFirst).first }
        var result = unique.filter { $0.provider != .codex }
        let threads = Dictionary(grouping: unique.filter { $0.provider == .codex }) {
            $0.navigationSourceID ?? $0.sourceID
        }

        for (threadID, members) in threads {
            let parentVersions = versionsByID[PetTaskSummary.identifier(provider: .codex, sourceID: threadID)] ?? []
            result.append(consolidate(threadID: threadID, members: members, parentVersions: parentVersions))
        }
        return result.sorted(by: displayOrder)
    }

    private static func consolidate(
        threadID: String,
        members: [PetTaskSummary],
        parentVersions: [PetTaskSummary]
    ) -> PetTaskSummary {
        // Every dictionary group is nonempty. Attention outranks running work;
        // a completed parent cannot hide a child that still needs the user.
        let strongest = members.sorted(by: displayOrder)[0]
        let parents = parentVersions.sorted(by: newestFirst)
        let project = parents.first { $0.project != .other }?.project
            ?? members.sorted(by: newestFirst).first { $0.project != .other }?.project
            ?? .other
        let title = parents.first(where: isNamedParent)?.title
            ?? fallbackTitle(threadID: threadID, project: project)
        let sameState = members.filter { $0.status == strongest.status }.sorted(by: newestFirst)
        let detail = sameState.first { isMeaningfulDetail($0.detail) }?.detail ?? strongest.detail

        return PetTaskSummary(
            sourceID: threadID,
            navigationSourceID: threadID,
            provider: .codex,
            title: title,
            detail: detail,
            status: strongest.status,
            project: project,
            updatedAt: members.map(\.updatedAt).max() ?? strongest.updatedAt,
            deepLinkURL: CodexThreadDeepLink.url(forThreadID: threadID)
        )
    }

    private static func fallbackTitle(threadID: String, project: PetTaskProject) -> String {
        let projectName = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if project != .other, !projectName.isEmpty {
            return "Task in \(projectName)"
        }
        let identity = threadID.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let shortIdentity = identity.count > 12 ? "…\(identity.suffix(8))" : identity
        return shortIdentity.isEmpty ? "Codex task" : "Codex task · \(shortIdentity)"
    }

    private static func isNamedParent(_ task: PetTaskSummary) -> Bool {
        let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !title.isEmpty && title != "Codex task"
            && title != fallbackTitle(threadID: task.navigationSourceID ?? task.sourceID, project: task.project)
    }

    private static func isMeaningfulDetail(_ detail: String) -> Bool {
        let normalized = detail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !normalized.isEmpty && !genericDetails.contains(normalized)
    }

    private static let genericDetails: Set<String> = [
        "working", "running", "waiting for permission", "waiting for input",
        "needs attention", "a tool failed", "completed", "finished recently",
        "recent", "recent activity", "recent codex activity", "session started",
    ]

    private static func priority(_ status: PetTaskStatus) -> Int {
        switch status {
        case .failed, .waiting: 0
        case .running: 1
        case .completed: 2
        case .recent: 3
        }
    }

    private static func displayOrder(_ left: PetTaskSummary, _ right: PetTaskSummary) -> Bool {
        if priority(left.status) != priority(right.status) {
            return priority(left.status) < priority(right.status)
        }
        if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
        if left.id != right.id { return left.id < right.id }
        return stableTieBreak(left, right)
    }

    private static func newestFirst(_ left: PetTaskSummary, _ right: PetTaskSummary) -> Bool {
        if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
        if priority(left.status) != priority(right.status) {
            return priority(left.status) < priority(right.status)
        }
        return stableTieBreak(left, right)
    }

    private static func stableTieBreak(_ left: PetTaskSummary, _ right: PetTaskSummary) -> Bool {
        let leftFields = [left.status.rawValue, left.id, left.title, left.detail,
                          left.project.id, left.project.name, left.project.path ?? "",
                          left.navigationSourceID ?? "", left.deepLinkURL?.absoluteString ?? ""]
        let rightFields = [right.status.rawValue, right.id, right.title, right.detail,
                           right.project.id, right.project.name, right.project.path ?? "",
                           right.navigationSourceID ?? "", right.deepLinkURL?.absoluteString ?? ""]
        return leftFields.lexicographicallyPrecedes(rightFields)
    }
}

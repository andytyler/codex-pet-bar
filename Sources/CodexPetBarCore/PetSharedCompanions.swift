import Foundation

/// Bounded membership for a shared playfield. Current work owns capacity;
/// finished participants can stay without being counted as active work.
public enum PetSharedCompanions {
    public static func strip(
        tasks: [PetTaskSummary],
        previousTasks: [PetTaskSummary] = [],
        now: Date = Date(),
        limit: Int = 4
    ) -> PetTaskCompanionStrip {
        let capacity = min(4, max(0, limit))
        let currentByID = Dictionary(grouping: tasks, by: \.id).compactMapValues {
            $0.sorted(by: newestFirst).first
        }
        var seenPrevious = Set<String>()
        let previous = previousTasks.filter { seenPrevious.insert($0.id).inserted }
        let previousPositions = Dictionary(uniqueKeysWithValues: previous.enumerated().map { ($0.element.id, $0.offset) })

        // Attention may displace working or idle pets. Within a priority tier,
        // retain participants already visible before admitting newcomers.
        let active = currentByID.values.filter { isActive($0.status) }.sorted { left, right in
            if priority(left.status) != priority(right.status) {
                return priority(left.status) < priority(right.status)
            }
            let leftPosition = previousPositions[left.id] ?? Int.max
            let rightPosition = previousPositions[right.id] ?? Int.max
            if leftPosition != rightPosition { return leftPosition < rightPosition }
            return newestFirst(left, right)
        }
        var selected = Array(active.prefix(capacity))
        var selectedIDs = Set(selected.map(\.id))

        for old in previous where selected.count < capacity && !selectedIDs.contains(old.id) {
            let retained = currentByID[old.id] ?? standing(old)
            guard !isActive(retained.status) else { continue }
            selected.append(retained)
            selectedIDs.insert(retained.id)
        }

        // On a quiet first entry, a few genuinely recent threads make useful
        // companions. Do not fill a working playfield with unrelated history.
        if previous.isEmpty && active.isEmpty {
            selected = Array(currentByID.values.filter {
                let age = now.timeIntervalSince($0.updatedAt)
                return !isActive($0.status) && age >= 0 && age <= 24 * 60 * 60
            }.sorted(by: newestFirst).prefix(min(capacity, 3)))
            selectedIDs = Set(selected.map(\.id))
        }

        // Priority chooses membership, not new positions: pets that survive
        // an update keep their relative order instead of sorting on each state change.
        let selectedByID = Dictionary(uniqueKeysWithValues: selected.map { ($0.id, $0) })
        let survivors = previous.compactMap { selectedByID[$0.id] }
        let survivorIDs = Set(survivors.map(\.id))
        let visible = survivors + selected.filter { !survivorIDs.contains($0.id) }
        let overflow = active.filter { !selectedIDs.contains($0.id) }
        return PetTaskCompanionStrip(
            visibleTasks: visible,
            overflowCount: overflow.count,
            attentionOverflowCount: overflow.filter { isAttention($0.status) }.count
        )
    }

    private static func standing(_ task: PetTaskSummary) -> PetTaskSummary {
        guard isActive(task.status) else { return task }
        // A missing current record is not evidence that its old run continues
        // or that it completed. Keep its identity, with a neutral recent state.
        return PetTaskSummary(sourceID: task.sourceID, navigationSourceID: task.navigationSourceID,
            provider: task.provider, title: task.title, detail: "Recent activity", status: .recent,
            project: task.project, updatedAt: task.updatedAt, deepLinkURL: task.deepLinkURL)
    }

    private static func isActive(_ status: PetTaskStatus) -> Bool {
        status == .running || isAttention(status)
    }

    private static func isAttention(_ status: PetTaskStatus) -> Bool {
        status == .waiting || status == .failed
    }

    private static func priority(_ status: PetTaskStatus) -> Int {
        switch status {
        case .waiting, .failed: 0
        case .running: 1
        case .completed, .recent: 2
        }
    }

    private static func newestFirst(_ left: PetTaskSummary, _ right: PetTaskSummary) -> Bool {
        if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
        if priority(left.status) != priority(right.status) {
            return priority(left.status) < priority(right.status)
        }
        let leftFields = [left.id, left.status.rawValue, left.title, left.detail,
                          left.project.id, left.project.name, left.project.path ?? "",
                          left.navigationSourceID ?? "", left.deepLinkURL?.absoluteString ?? ""]
        let rightFields = [right.id, right.status.rawValue, right.title, right.detail,
                           right.project.id, right.project.name, right.project.path ?? "",
                           right.navigationSourceID ?? "", right.deepLinkURL?.absoluteString ?? ""]
        return leftFields.lexicographicallyPrecedes(rightFields)
    }
}

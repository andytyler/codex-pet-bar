import Foundation

/// Persistent task-to-pet choices. Keys are `PetTaskSummary.id`, so providers
/// that reuse the same source identifier still receive independent companions.
public enum PetTaskCompanions {
    /// Keeps existing choices, including tasks temporarily absent from the feed.
    /// New choices prefer pets not already used by a task in the supplied feed.
    /// Explicit overrides and existing choices may intentionally share a pet.
    /// The caller owns persistence and any limit on retained inactive task IDs.
    public static func assignments(
        tasks: [PetTaskSummary],
        pets: [PetPackage],
        previous: [String: String] = [:],
        overrides: [String: String] = [:]
    ) -> [String: String] {
        let petIDs = Array(Set(pets.map(\.id).filter { !$0.isEmpty })).sorted()
        guard !petIDs.isEmpty else { return [:] }
        let available = Set(petIDs)
        var result = previous.filter { !$0.key.isEmpty && available.contains($0.value) }
        for (taskID, petID) in overrides where !taskID.isEmpty && available.contains(petID) {
            result[taskID] = petID
        }

        let taskIDs = Set(tasks.map(\.id)).sorted()
        var usedPetIDs = Set(taskIDs.compactMap { result[$0] })
        for taskID in taskIDs where result[taskID] == nil {
            let start = Int(stableHash(taskID) % UInt64(petIDs.count))
            let preferred = (0..<petIDs.count)
                .map { petIDs[(start + $0) % petIDs.count] }
            let selected = preferred.first { !usedPetIDs.contains($0) } ?? petIDs[start]
            result[taskID] = selected
            usedPetIDs.insert(selected)
        }
        return result
    }

    /// A compact menu-bar strip contains active tasks only. Attention leads
    /// running work; task IDs keep positions stable as timestamps refresh.
    public static func strip(
        tasks: [PetTaskSummary],
        limit: Int = 4
    ) -> PetTaskCompanionStrip {
        // A feed can briefly contain both an indexed task and its live event.
        // Prefer the newest reconciled summary without creating duplicate pets.
        let uniqueTasks = Dictionary(grouping: tasks, by: \.id).compactMap { _, copies in
            copies.sorted(by: preferredSummary).first
        }
        let active = uniqueTasks.filter { isActive($0.status) }.sorted { left, right in
            let leftPriority = priority(left.status)
            let rightPriority = priority(right.status)
            if leftPriority != rightPriority { return leftPriority < rightPriority }
            return left.id < right.id
        }
        let visibleCount = min(max(0, limit), 4, active.count)
        let overflow = active.dropFirst(visibleCount)
        return PetTaskCompanionStrip(
            visibleTasks: Array(active.prefix(visibleCount)),
            overflowCount: overflow.count,
            attentionOverflowCount: overflow.filter { priority($0.status) == 0 }.count
        )
    }

    private static func isActive(_ status: PetTaskStatus) -> Bool {
        switch status {
        case .waiting, .failed, .running: true
        case .completed, .recent: false
        }
    }

    private static func priority(_ status: PetTaskStatus) -> Int {
        switch status {
        case .waiting, .failed: 0
        case .running: 1
        case .completed, .recent: 2
        }
    }

    private static func preferredSummary(_ left: PetTaskSummary, _ right: PetTaskSummary) -> Bool {
        if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
        if priority(left.status) != priority(right.status) {
            return priority(left.status) < priority(right.status)
        }
        if left.status != right.status { return left.status.rawValue < right.status.rawValue }
        if left.title != right.title { return left.title < right.title }
        return left.detail < right.detail
    }

    /// FNV-1a has no per-process seed, unlike Swift's `Hasher`.
    private static func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}

public struct PetTaskCompanionStrip: Equatable, Sendable {
    public let visibleTasks: [PetTaskSummary]
    public let overflowCount: Int
    public let attentionOverflowCount: Int

    public init(visibleTasks: [PetTaskSummary], overflowCount: Int, attentionOverflowCount: Int) {
        self.visibleTasks = visibleTasks
        self.overflowCount = overflowCount
        self.attentionOverflowCount = attentionOverflowCount
    }
}

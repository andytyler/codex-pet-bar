import Foundation

public enum PetTaskStatus: String, CaseIterable, Sendable {
    case running
    case waiting
    case completed
    case failed
    case recent
}

public struct PetTaskProject: Equatable, Hashable, Sendable {
    public static let other = PetTaskProject(id: "other", name: "Other", path: nil)

    public let id: String
    public let name: String
    public let path: String?

    public init(id: String, name: String, path: String?) {
        self.id = id
        self.name = name
        self.path = path
    }

    public static func derived(fromWorkspace workspace: String?) -> PetTaskProject {
        guard let workspace else {
            return .other
        }

        let trimmed = workspace.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .other
        }

        let standardized = (trimmed as NSString).standardizingPath
        let path = standardized
        guard !path.isEmpty else {
            return .other
        }

        let name = (path as NSString).lastPathComponent
        return PetTaskProject(
            id: "path:\(path)",
            name: name.isEmpty ? path : name,
            path: standardized
        )
    }
}

public struct PetTaskSummary: Equatable, Identifiable, Sendable {
    public static let maximumTitleLength = 70
    public static let maximumDetailLength = 160

    /// Namespacing the source identifier prevents identical session IDs from
    /// different agents from colliding in SwiftUI lists or merge dictionaries.
    public let id: String
    public let sourceID: String
    /// The real resumable parent when `sourceID` identifies a child run.
    public let navigationSourceID: String?
    public let provider: PetProvider
    public let title: String
    public let detail: String
    public let status: PetTaskStatus
    public let project: PetTaskProject
    public let updatedAt: Date
    public let deepLinkURL: URL?

    public init(
        sourceID: String,
        navigationSourceID: String? = nil,
        provider: PetProvider,
        title: String,
        detail: String,
        status: PetTaskStatus,
        project: PetTaskProject,
        updatedAt: Date,
        deepLinkURL: URL? = nil
    ) {
        self.id = Self.identifier(provider: provider, sourceID: sourceID)
        self.sourceID = sourceID
        self.navigationSourceID = navigationSourceID
        self.provider = provider
        self.title = Self.concise(title, limit: Self.maximumTitleLength, fallback: Self.fallbackTitle(for: provider))
        self.detail = Self.concise(detail, limit: Self.maximumDetailLength, fallback: "Recent activity")
        self.status = status
        self.project = project
        self.updatedAt = updatedAt
        self.deepLinkURL = deepLinkURL
    }

    public static func identifier(provider: PetProvider, sourceID: String) -> String {
        "\(provider.rawValue):\(sourceID)"
    }

    static func concise(_ text: String, limit: Int, fallback: String) -> String {
        let normalized = text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        let value = normalized.isEmpty ? fallback : normalized
        guard limit > 3, value.count > limit else {
            return String(value.prefix(max(0, limit)))
        }

        return String(value.prefix(limit - 3)) + "..."
    }

    private static func fallbackTitle(for provider: PetProvider) -> String {
        switch provider {
        case .codex:
            "Codex task"
        case .claude:
            "Claude Code task"
        case .cursor:
            "Cursor task"
        }
    }
}

public struct PetTaskProjectGroup: Equatable, Identifiable, Sendable {
    public var id: String { project.id }

    public let project: PetTaskProject
    public let tasks: [PetTaskSummary]

    public init(project: PetTaskProject, tasks: [PetTaskSummary]) {
        self.project = project
        self.tasks = tasks
    }
}

public enum PetTaskSummaryGrouping {
    /// Produces deterministic groups in newest-project-first order. Tasks with
    /// equal timestamps retain their input order.
    public static func groups(tasks: [PetTaskSummary]) -> [PetTaskProjectGroup] {
        let recencyOrdered = tasks.enumerated().sorted { left, right in
            if left.element.updatedAt != right.element.updatedAt {
                return left.element.updatedAt > right.element.updatedAt
            }
            return left.offset < right.offset
        }.map(\.element)

        var groups: [PetTaskProjectGroup] = []
        var indexesByProjectID: [String: Int] = [:]

        for task in recencyOrdered {
            if let index = indexesByProjectID[task.project.id] {
                let existing = groups[index]
                groups[index] = PetTaskProjectGroup(project: existing.project, tasks: existing.tasks + [task])
            } else {
                indexesByProjectID[task.project.id] = groups.count
                groups.append(PetTaskProjectGroup(project: task.project, tasks: [task]))
            }
        }

        return groups
    }
}

public struct CodexRolloutTaskMetadata: Equatable, Sendable {
    public let threadID: String
    public let workspace: String?
    public let latestDetail: String?
    public let latestMessageDate: Date?

    public init(threadID: String, workspace: String?, latestDetail: String?, latestMessageDate: Date?) {
        self.threadID = threadID
        self.workspace = workspace
        self.latestDetail = latestDetail
        self.latestMessageDate = latestMessageDate
    }
}

public struct PetTaskSummaryConfiguration: Equatable, Sendable {
    public var recentThreadLimit: Int
    public var sessionIndexTailByteLimit: Int
    public var rolloutHeadByteLimit: Int
    public var rolloutTailByteLimit: Int
    public var maximumDirectoryEntriesPerDay: Int
    public var adjacentDayRadius: Int
    public var providerTaskLimit: Int
    public var providerEventRecentWindow: TimeInterval
    public var activeStatusWindow: TimeInterval
    public var waitingAndFailureStatusWindow: TimeInterval
    public var terminalSummaryFallbackWindow: TimeInterval

    public init(
        recentThreadLimit: Int = 18,
        sessionIndexTailByteLimit: Int = 1_048_576,
        rolloutHeadByteLimit: Int = 65_536,
        rolloutTailByteLimit: Int = 262_144,
        maximumDirectoryEntriesPerDay: Int = 2_048,
        adjacentDayRadius: Int = 1,
        providerTaskLimit: Int = 12,
        providerEventRecentWindow: TimeInterval = 7 * 24 * 60 * 60,
        activeStatusWindow: TimeInterval = 6 * 60 * 60,
        waitingAndFailureStatusWindow: TimeInterval = 24 * 60 * 60,
        terminalSummaryFallbackWindow: TimeInterval = 5
    ) {
        self.recentThreadLimit = recentThreadLimit
        self.sessionIndexTailByteLimit = sessionIndexTailByteLimit
        self.rolloutHeadByteLimit = rolloutHeadByteLimit
        self.rolloutTailByteLimit = rolloutTailByteLimit
        self.maximumDirectoryEntriesPerDay = maximumDirectoryEntriesPerDay
        self.adjacentDayRadius = adjacentDayRadius
        self.providerTaskLimit = providerTaskLimit
        self.providerEventRecentWindow = providerEventRecentWindow
        self.activeStatusWindow = activeStatusWindow
        self.waitingAndFailureStatusWindow = waitingAndFailureStatusWindow
        self.terminalSummaryFallbackWindow = terminalSummaryFallbackWindow
    }
}

/// Synchronous bounded file reader. Call this from a utility task rather than
/// the main actor; all transformation and grouping APIs below are pure.
public enum CodexTaskSummaryReader {
    public static func read(
        sessionIndexURL: URL,
        sessionsRootURL: URL,
        providerEvents: [CodexPetEvent] = [],
        now: Date = Date(),
        configuration: PetTaskSummaryConfiguration = .init()
    ) -> [PetTaskSummary] {
        let threads = CodexSessionIndexLog.readRecentThreads(
            from: sessionIndexURL,
            limit: configuration.recentThreadLimit,
            tailByteLimit: configuration.sessionIndexTailByteLimit
        )

        let rolloutURLs = rolloutURLs(
            for: threads,
            sessionsRootURL: sessionsRootURL,
            configuration: configuration
        )
        var rolloutsByThreadID: [String: CodexRolloutTaskMetadata] = [:]
        for thread in threads {
            guard
                let rolloutURL = rolloutURLs[thread.id],
                let metadata = readRollout(
                    threadID: thread.id,
                    from: rolloutURL,
                    headByteLimit: configuration.rolloutHeadByteLimit,
                    tailByteLimit: configuration.rolloutTailByteLimit
                )
            else {
                continue
            }
            rolloutsByThreadID[thread.id] = metadata
        }

        let codexTasks = PetTaskSummaryBuilder.codexTasks(
            threads: threads,
            rolloutsByThreadID: rolloutsByThreadID,
            providerEvents: providerEvents,
            now: now,
            configuration: configuration
        )
        let indexedCodexThreadIDs = Set(threads.map(\.id))
        let unindexedActiveCodexTasks = PetTaskSummaryBuilder.providerTasks(
            events: providerEvents,
            excluding: [.claude, .cursor],
            now: now,
            configuration: configuration
        ).filter { task in
            !indexedCodexThreadIDs.contains(task.sourceID)
                && PetTaskSummaryBuilder.isAttentionStatus(task.status)
        }
        let otherProviderTasks = PetTaskSummaryBuilder.providerTasks(
            events: providerEvents,
            excluding: [.codex],
            now: now,
            configuration: configuration
        )

        return PetTaskSummaryBuilder.recencyOrdered(
            codexTasks + unindexedActiveCodexTasks + otherProviderTasks
        )
    }

    static func readRollout(
        threadID: String,
        from url: URL,
        headByteLimit: Int,
        tailByteLimit: Int
    ) -> CodexRolloutTaskMetadata? {
        guard
            let head = try? BoundedTaskFileReader.headData(from: url, byteLimit: headByteLimit),
            let tail = try? BoundedTaskFileReader.tailCompleteLineData(from: url, byteLimit: tailByteLimit)
        else {
            return nil
        }

        return CodexRolloutTaskParser.metadata(threadID: threadID, headData: head, tailData: tail)
    }

    static func rolloutURLs(
        for threads: [CodexThreadSummary],
        sessionsRootURL: URL,
        configuration: PetTaskSummaryConfiguration
    ) -> [String: URL] {
        let eligibleThreads = Array(threads.prefix(max(0, configuration.recentThreadLimit)))
        guard !eligibleThreads.isEmpty, configuration.maximumDirectoryEntriesPerDay > 0 else {
            return [:]
        }

        let calendar = CodexSessionDay.calendar
        var threadIDsByDay: [String: Set<String>] = [:]
        for thread in eligibleThreads {
            let dates = [thread.updatedAt, CodexSessionDay.uuidV7Date(thread.id)].compactMap { $0 }
            for date in dates {
                for delta in -max(0, configuration.adjacentDayRadius)...max(0, configuration.adjacentDayRadius) {
                    guard
                        let day = calendar.date(byAdding: .day, value: delta, to: date),
                        let key = CodexSessionDay.pathKey(for: day)
                    else {
                        continue
                    }
                    threadIDsByDay[key, default: []].insert(thread.id)
                }
            }
        }

        var results: [String: URL] = [:]
        for dayKey in threadIDsByDay.keys.sorted().reversed() {
            guard var remainingIDs = threadIDsByDay[dayKey] else {
                continue
            }
            remainingIDs.subtract(results.keys)
            guard !remainingIDs.isEmpty else {
                continue
            }

            let directoryURL = sessionsRootURL.appendingPathComponent(dayKey, isDirectory: true)
            guard let enumerator = FileManager.default.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            ) else {
                continue
            }

            var visitedCount = 0
            while
                visitedCount < configuration.maximumDirectoryEntriesPerDay,
                let candidate = enumerator.nextObject() as? URL
            {
                visitedCount += 1
                let filename = candidate.lastPathComponent
                guard filename.hasPrefix("rollout-"), filename.hasSuffix(".jsonl") else {
                    continue
                }

                for threadID in remainingIDs where filename.hasSuffix("-\(threadID).jsonl") {
                    if
                        let existing = results[threadID],
                        existing.lastPathComponent >= filename
                    {
                        continue
                    }
                    results[threadID] = candidate
                }
            }
        }

        return results
    }
}

public enum PetTaskSummaryBuilder {
    public static func codexTasks(
        threads: [CodexThreadSummary],
        rolloutsByThreadID: [String: CodexRolloutTaskMetadata],
        providerEvents: [CodexPetEvent] = [],
        now: Date = Date(),
        configuration: PetTaskSummaryConfiguration = .init()
    ) -> [PetTaskSummary] {
        let latestContexts = latestEventContextsByIdentity(
            providerEvents,
            now: now,
            configuration: configuration,
            terminalSummaryFallbackWindow: configuration.terminalSummaryFallbackWindow
        )

        return recencyOrdered(threads.map { thread in
            let rollout = rolloutsByThreadID[thread.id]
            let context = latestContexts[PetTaskSummary.identifier(provider: .codex, sourceID: thread.id)]
            let event = context?.latestEvent
            let updatedAt = [thread.updatedAt, rollout?.latestMessageDate, event.map { Date(timeIntervalSince1970: $0.timestamp) }]
                .compactMap { $0 }
                .max() ?? .distantPast
            let eventSummary = context?.summary
            let eventSummaryDate = context?.summaryEvent.map { Date(timeIntervalSince1970: $0.timestamp) }
            let selectedDetail: String
            if
                let eventSummary,
                (rollout?.latestMessageDate ?? .distantPast) <= (eventSummaryDate ?? .distantPast)
            {
                selectedDetail = eventSummary
            } else {
                selectedDetail = rollout?.latestDetail
                    ?? eventSummary
                    ?? detail(for: context?.lifecycleState, provider: .codex, now: now, configuration: configuration)
            }

            return PetTaskSummary(
                sourceID: thread.id,
                navigationSourceID: thread.id,
                provider: .codex,
                title: thread.title,
                detail: selectedDetail,
                status: status(for: context?.lifecycleState, now: now, configuration: configuration),
                project: PetTaskProject.derived(fromWorkspace: rollout?.workspace ?? event?.workspace),
                updatedAt: updatedAt,
                deepLinkURL: CodexThreadDeepLink.url(forThreadID: thread.id)
            )
        })
    }

    /// Creates safe cross-provider cards using only normalized event metadata.
    /// Prompt and raw transcript text are intentionally not part of this API;
    /// the only prose accepted is the hook's bounded terminal assistant summary.
    public static func providerTasks(
        events: [CodexPetEvent],
        excluding excludedProviders: Set<PetProvider> = [],
        now: Date = Date(),
        configuration: PetTaskSummaryConfiguration = .init()
    ) -> [PetTaskSummary] {
        let cutoff = now.timeIntervalSince1970 - max(0, configuration.providerEventRecentWindow)
        let stableWorkspaces = stableWorkspaceByIdentity(events)
        let latest = latestEventContextsByIdentity(
            events,
            now: now,
            configuration: configuration,
            terminalSummaryFallbackWindow: configuration.terminalSummaryFallbackWindow
        ).values
            .filter { context in
                !excludedProviders.contains(context.latestEvent.provider)
                    && !(context.latestEvent.sessionID?.isEmpty ?? true)
            }
            .sorted { left, right in
                if left.latestEvent.timestamp != right.latestEvent.timestamp {
                    return left.latestEvent.timestamp > right.latestEvent.timestamp
                }
                return identity(for: left.latestEvent) < identity(for: right.latestEvent)
            }

        let candidates = latest.map { context in
            (
                context: context,
                status: status(for: context.lifecycleState, now: now, configuration: configuration)
            )
        }
        let attentionCandidates = candidates.filter { isAttentionStatus($0.status) }
        let boundedHistoryCandidates = candidates
            .filter { !isAttentionStatus($0.status) && $0.context.latestEvent.timestamp >= cutoff }
            .prefix(max(0, configuration.providerTaskLimit))

        let tasks = (attentionCandidates + boundedHistoryCandidates).compactMap { candidate -> PetTaskSummary? in
            let event = candidate.context.latestEvent
            guard let sourceID = event.sessionID else {
                return nil
            }
            return PetTaskSummary(
                sourceID: sourceID,
                navigationSourceID: event.parentSessionID ?? sourceID,
                provider: event.provider,
                title: fallbackTitle(for: event.provider),
                detail: detail(
                    for: candidate.context.lifecycleState,
                    provider: event.provider,
                    assistantSummary: candidate.context.summary,
                    now: now,
                    configuration: configuration
                ),
                status: candidate.status,
                project: PetTaskProject.derived(
                    fromWorkspace: stableWorkspaces[identity(for: event)] ?? event.workspace
                ),
                updatedAt: Date(timeIntervalSince1970: event.timestamp),
                deepLinkURL: event.provider == .codex
                    ? CodexThreadDeepLink.url(forThreadID: event.parentSessionID ?? sourceID)
                    : nil
            )
        }
        return recencyOrdered(tasks)
    }

    /// Applies exactly the active session snapshot used by the menu-bar flags.
    /// Rollout state is evidence, not a fabricated hook: it can reopen a stopped
    /// session or keep a child active independently of its parent's completion.
    public static func reconciling(
        tasks: [PetTaskSummary],
        snapshot: CodexPetActivitySnapshot,
        completedCodexScopes: [CodexRolloutActivityScope] = [],
        now: Date = Date()
    ) -> [PetTaskSummary] {
        var activeByID: [String: CodexPetActiveScope] = [:]
        for scope in snapshot.activeScopes {
            activeByID[PetTaskSummary.identifier(provider: scope.provider,
                sourceID: scope.sessionID ?? scope.scopedIdentity)] = scope
        }
        let completed = Set(completedCodexScopes.map(\.sessionID))
        var result = tasks.map { task -> PetTaskSummary in
            let active = activeByID.removeValue(forKey: task.id)
            let status: PetTaskStatus
            if let active {
                status = taskStatus(active.activity)
            } else if task.provider == .codex,
                completed.contains(task.sourceID) || task.navigationSourceID.map(completed.contains) == true {
                status = .completed
            } else {
                status = isAttentionStatus(task.status) ? .recent : task.status
            }
            let navigationID = active?.parentSessionID ?? task.navigationSourceID
            return PetTaskSummary(sourceID: task.sourceID, navigationSourceID: navigationID,
                provider: task.provider, title: task.title,
                detail: status == task.status ? task.detail : taskDetail(status), status: status,
                project: task.project == .other ? PetTaskProject.derived(fromWorkspace: active?.workspace) : task.project,
                updatedAt: max(task.updatedAt, active?.timestamp.map(Date.init(timeIntervalSince1970:)) ?? task.updatedAt),
                deepLinkURL: task.provider == .codex
                    ? CodexThreadDeepLink.url(forThreadID: navigationID ?? task.sourceID) : task.deepLinkURL)
        }
        for scope in activeByID.values {
            let sourceID = scope.sessionID ?? scope.scopedIdentity
            let navigationID = scope.parentSessionID ?? sourceID
            let status = taskStatus(scope.activity)
            result.append(PetTaskSummary(sourceID: sourceID, navigationSourceID: navigationID,
                provider: scope.provider, title: fallbackTitle(for: scope.provider),
                detail: taskDetail(status), status: status,
                project: PetTaskProject.derived(fromWorkspace: scope.workspace),
                updatedAt: scope.timestamp.map(Date.init(timeIntervalSince1970:)) ?? now,
                deepLinkURL: scope.provider == .codex ? CodexThreadDeepLink.url(forThreadID: navigationID) : nil))
        }
        return recencyOrdered(result.sorted { $0.id < $1.id })
    }

    private static func taskStatus(_ activity: CodexActivity) -> PetTaskStatus {
        switch activity {
        case .running, .listening: .running
        case .reviewing: .waiting
        case .failed: .failed
        case .idle: .completed
        }
    }

    private static func taskDetail(_ status: PetTaskStatus) -> String {
        switch status {
        case .running: "Working"
        case .waiting: "Waiting for permission"
        case .failed: "A tool failed"
        case .completed: "Finished recently"
        case .recent: "Recent activity"
        }
    }

    private static func stableWorkspaceByIdentity(_ events: [CodexPetEvent]) -> [String: String] {
        var earliest: [String: (timestamp: TimeInterval, workspace: String)] = [:]
        for event in events {
            guard
                !(event.sessionID?.isEmpty ?? true),
                let workspace = event.workspace?.trimmingCharacters(in: .whitespacesAndNewlines),
                !workspace.isEmpty
            else {
                continue
            }
            let key = identity(for: event)
            if let existing = earliest[key], existing.timestamp <= event.timestamp {
                continue
            }
            earliest[key] = (event.timestamp, workspace)
        }
        return earliest.mapValues(\.workspace)
    }

    public static func recencyOrdered(_ tasks: [PetTaskSummary]) -> [PetTaskSummary] {
        tasks.enumerated().sorted { left, right in
            if left.element.updatedAt != right.element.updatedAt {
                return left.element.updatedAt > right.element.updatedAt
            }
            return left.offset < right.offset
        }.map(\.element)
    }

    static func isAttentionStatus(_ status: PetTaskStatus) -> Bool {
        switch status {
        case .running, .waiting, .failed:
            true
        case .completed, .recent:
            false
        }
    }

    private struct IndexedEvent {
        let event: CodexPetEvent
        let inputIndex: Int
    }

    private struct LatestEventContext {
        let latestEvent: CodexPetEvent
        let lifecycleState: CodexPetLifecycle.State
        let summaryEvent: CodexPetEvent?
        let summary: String?
    }

    private static func latestEventContextsByIdentity(
        _ events: [CodexPetEvent],
        now: Date,
        configuration: PetTaskSummaryConfiguration,
        terminalSummaryFallbackWindow: TimeInterval
    ) -> [String: LatestEventContext] {
        var eventsByIdentity: [String: [IndexedEvent]] = [:]
        var summaryEvents: [CodexPetEvent] = []
        for event in events {
            summaryEvents.append(contentsOf: event.lifecycleCheckpoint?.summaryEvents ?? [])
            summaryEvents.append(contentsOf: event.lifecycleCheckpoint?.workEvents ?? [])
            summaryEvents.append(contentsOf: event.lifecycleCheckpoint?.pendingPermissions ?? [])
            summaryEvents.append(event)
        }
        for (inputIndex, event) in summaryEvents.enumerated() {
            guard !(event.sessionID?.isEmpty ?? true) else {
                continue
            }
            eventsByIdentity[identity(for: event), default: []].append(
                IndexedEvent(event: event, inputIndex: inputIndex)
            )
        }

        var contexts: [String: LatestEventContext] = [:]
        for (identity, indexedEvents) in eventsByIdentity {
            let orderedEvents = indexedEvents.sorted { left, right in
                if left.event.timestamp != right.event.timestamp {
                    return left.event.timestamp < right.event.timestamp
                }
                return left.inputIndex < right.inputIndex
            }
            guard
                let lifecycleState = CodexPetLifecycle.reduce(
                    events: events.filter { self.identity(for: $0) == identity },
                    activeWindow: configuration.activeStatusWindow,
                    attentionWindow: configuration.waitingAndFailureStatusWindow,
                    now: now.timeIntervalSince1970
                ),
                let latestPosition = orderedEvents.lastIndex(where: {
                    $0.event == lifecycleState.event
                        || $0.event.lifecycleCheckpoint?.pendingPermissions.contains(lifecycleState.event) == true
                })
            else {
                continue
            }
            let latest = IndexedEvent(event: lifecycleState.event, inputIndex: orderedEvents[latestPosition].inputIndex)
            var selectedSummaryEvent: CodexPetEvent?
            var selectedSummary: String?

            for position in orderedEvents[...latestPosition].indices.reversed() {
                let candidate = orderedEvents[position]
                guard let summary = normalizedAssistantSummary(from: candidate.event) else {
                    continue
                }

                let interveningEvents = position < latestPosition
                    ? orderedEvents[orderedEvents.index(after: position)..<latestPosition]
                        .map(\.event)
                        .filter(CodexPetLifecycle.isStateBearing)
                    : []
                guard terminalSummaryBelongsToLatestEvent(
                    candidate.event,
                    latestEvent: latest.event,
                    interveningEvents: interveningEvents,
                    fallbackWindow: terminalSummaryFallbackWindow
                ) else {
                    continue
                }

                selectedSummaryEvent = candidate.event
                selectedSummary = summary
                break
            }

            contexts[identity] = LatestEventContext(
                latestEvent: latest.event,
                lifecycleState: lifecycleState,
                summaryEvent: selectedSummaryEvent,
                summary: selectedSummary
            )
        }
        return contexts
    }

    private static func terminalSummaryBelongsToLatestEvent(
        _ summaryEvent: CodexPetEvent,
        latestEvent: CodexPetEvent,
        interveningEvents: [CodexPetEvent],
        fallbackWindow: TimeInterval
    ) -> Bool {
        if summaryEvent == latestEvent {
            return true
        }

        let summaryTurnID = nonEmpty(summaryEvent.turnID)
        let latestTurnID = nonEmpty(latestEvent.turnID)
        if let summaryTurnID, let latestTurnID {
            return summaryTurnID == latestTurnID
        }

        guard isTerminalContinuation(latestEvent) else {
            return false
        }
        let elapsed = latestEvent.timestamp - summaryEvent.timestamp
        guard elapsed >= 0, elapsed <= max(0, fallbackWindow) else {
            return false
        }

        return interveningEvents.allSatisfy(CodexPetLifecycle.isTerminal)
    }

    private static func isTerminalContinuation(_ event: CodexPetEvent) -> Bool {
        CodexPetLifecycle.isTerminal(event)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func identity(for event: CodexPetEvent) -> String {
        PetTaskSummary.identifier(provider: event.provider, sourceID: event.sessionID ?? "")
    }

    private static func status(
        for state: CodexPetLifecycle.State?,
        now: Date,
        configuration: PetTaskSummaryConfiguration
    ) -> PetTaskStatus {
        guard
            let state,
            state.isCurrent(
                at: now.timeIntervalSince1970,
                activeWindow: configuration.activeStatusWindow,
                attentionWindow: configuration.waitingAndFailureStatusWindow,
                terminalWindow: configuration.waitingAndFailureStatusWindow
            )
        else {
            return .recent
        }

        switch state.phase {
        case .listening, .running:
            return .running
        case .reviewing:
            return .waiting
        case .failed:
            return .failed
        case .completed:
            return .completed
        }
    }

    private static func detail(
        for state: CodexPetLifecycle.State?,
        provider: PetProvider,
        assistantSummary: String? = nil,
        now: Date,
        configuration: PetTaskSummaryConfiguration
    ) -> String {
        guard let state else {
            return "Recent \(providerName(provider)) activity"
        }

        if let assistantSummary {
            return assistantSummary
        }

        guard state.isCurrent(
            at: now.timeIntervalSince1970,
            activeWindow: configuration.activeStatusWindow,
            attentionWindow: configuration.waitingAndFailureStatusWindow,
            terminalWindow: configuration.waitingAndFailureStatusWindow
        ) else {
            return "Recent \(providerName(provider)) activity"
        }

        switch state.phase {
        case .reviewing:
            return "Waiting for permission"
        case .failed:
            return "A tool failed"
        case .listening:
            return "Session started"
        case .running:
            return "Working"
        case .completed:
            return "Finished recently"
        }
    }

    private static func fallbackTitle(for provider: PetProvider) -> String {
        switch provider {
        case .codex:
            "Codex task"
        case .claude:
            "Claude Code task"
        case .cursor:
            "Cursor task"
        }
    }

    private static func normalizedAssistantSummary(from event: CodexPetEvent?) -> String? {
        guard let summary = event?.assistantSummary else {
            return nil
        }
        let normalized = summary.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return normalized.isEmpty ? nil : normalized
    }

    private static func providerName(_ provider: PetProvider) -> String {
        switch provider {
        case .codex:
            "Codex"
        case .claude:
            "Claude Code"
        case .cursor:
            "Cursor"
        }
    }
}

enum CodexRolloutTaskParser {
    static func metadata(threadID: String, headData: Data, tailData: Data) -> CodexRolloutTaskMetadata {
        let headText = String(decoding: headData, as: UTF8.self)
        let tailText = String(decoding: tailData, as: UTF8.self)

        let workspace = sessionWorkspace(fromHeadText: headText)
        var latestMessage: CodexRolloutMessage?
        for line in tailText.split(whereSeparator: \.isNewline) {
            if let message = CodexRolloutMessage(jsonLine: String(line)) {
                latestMessage = message
            }
        }

        return CodexRolloutTaskMetadata(
            threadID: threadID,
            workspace: workspace,
            latestDetail: latestMessage?.text,
            latestMessageDate: latestMessage?.timestamp
        )
    }

    static func sessionWorkspace(fromHeadText text: String) -> String? {
        if let newline = text.firstIndex(of: "\n") {
            let firstLine = String(text[..<newline])
            if
                let data = firstLine.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                object["type"] as? String == "session_meta",
                let payload = object["payload"] as? [String: Any],
                let workspace = payload["cwd"] as? String,
                !workspace.isEmpty
            {
                return workspace
            }
        }

        guard let sessionMetaRange = text.range(of: "\"session_meta\"") else {
            return nil
        }

        let sessionText = text[sessionMetaRange.lowerBound...]
        guard
            let keyRange = sessionText.range(of: "\"cwd\""),
            let colon = sessionText[keyRange.upperBound...].firstIndex(of: ":")
        else {
            return nil
        }

        let afterColon = sessionText[sessionText.index(after: colon)...]
        guard let openingQuote = afterColon.firstIndex(where: { !$0.isWhitespace }), afterColon[openingQuote] == "\"" else {
            return nil
        }

        var cursor = afterColon.index(after: openingQuote)
        var escaped = false
        while cursor < afterColon.endIndex {
            let character = afterColon[cursor]
            if character == "\"", !escaped {
                let literal = String(afterColon[openingQuote...cursor])
                return try? JSONDecoder().decode(String.self, from: Data(literal.utf8))
            }
            if character == "\\" {
                escaped.toggle()
            } else {
                escaped = false
            }
            cursor = afterColon.index(after: cursor)
        }
        return nil
    }
}

enum BoundedTaskFileReader {
    static func headData(from url: URL, byteLimit: Int) throws -> Data {
        guard byteLimit > 0 else {
            return Data()
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: byteLimit) ?? Data()
    }

    static func tailCompleteLineData(from url: URL, byteLimit: Int) throws -> Data {
        guard byteLimit > 0 else {
            return Data()
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let size = try handle.seekToEnd()
        let limit = UInt64(byteLimit)
        let start = size > limit ? size - limit : 0
        try handle.seek(toOffset: start)
        var data = try handle.read(upToCount: byteLimit) ?? Data()

        if start > 0 {
            guard let firstNewline = data.firstIndex(of: UInt8(ascii: "\n")) else {
                return Data()
            }
            data = data.suffix(from: data.index(after: firstNewline))
        }

        if data.last != UInt8(ascii: "\n") {
            guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else {
                return Data()
            }
            data = data.prefix(through: lastNewline)
        }

        return data
    }
}

enum CodexSessionDay {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    static func uuidV7Date(_ rawValue: String) -> Date? {
        let compact = rawValue.replacingOccurrences(of: "-", with: "")
        guard compact.count == 32 else {
            return nil
        }

        let versionIndex = compact.index(compact.startIndex, offsetBy: 12)
        guard compact[versionIndex] == "7" else {
            return nil
        }

        let timestampHex = compact.prefix(12)
        guard let milliseconds = UInt64(timestampHex, radix: 16) else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
    }

    static func pathKey(for date: Date) -> String? {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return nil
        }
        return String(format: "%04d/%02d/%02d", year, month, day)
    }
}

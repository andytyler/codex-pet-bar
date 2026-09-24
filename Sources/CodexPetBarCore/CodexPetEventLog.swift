import Foundation

public enum PetProvider: String, CaseIterable, Codable, Hashable, Sendable {
    case codex
    case claude
    case cursor
}

/// A reduced session checkpoint, shared with the hook rotation writer. Keeping
/// turn tombstones and outstanding requests makes replay independent of log size.
public struct CodexPetLifecycleCheckpoint: Codable, Equatable, Hashable, Sendable {
    let phase: String
    let currentTurnID: String?
    let completedTurnID: String?
    let completedTurns: [String: TimeInterval]
    let pendingPermissions: [CodexPetEvent]
    let workPhase: String?
    let workEvents: [CodexPetEvent]?
    let summaryEvents: [CodexPetEvent]?
    let reducedThrough: TimeInterval?
    let turnStartedAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case phase
        case currentTurnID = "current_turn_id"
        case completedTurnID = "completed_turn_id"
        case completedTurns = "completed_turns"
        case pendingPermissions = "pending_permissions"
        case workPhase = "work_phase"
        case workEvents = "work_events"
        case summaryEvents = "summary_events"
        case reducedThrough = "reduced_through"
        case turnStartedAt = "turn_started_at"
    }
}

public struct CodexPetEvent: Codable, Equatable, Hashable, Sendable {
    public let kind: String
    public let timestamp: TimeInterval
    public let provider: PetProvider
    public let workspace: String?
    public let sessionID: String?
    public let parentSessionID: String?
    public let turnID: String?
    public let toolName: String?
    public let toolUseID: String?
    public let permissionRequestID: String?
    public let lifecycleCheckpoint: CodexPetLifecycleCheckpoint?
    public let hookEventName: String?
    public let assistantSummary: String?
    public let status: String?

    public init(
        kind: String,
        timestamp: TimeInterval,
        provider: PetProvider = .codex,
        workspace: String? = nil,
        sessionID: String? = nil,
        parentSessionID: String? = nil,
        turnID: String? = nil,
        toolName: String? = nil,
        hookEventName: String? = nil,
        assistantSummary: String? = nil,
        status: String? = nil,
        toolUseID: String? = nil,
        permissionRequestID: String? = nil,
        lifecycleCheckpoint: CodexPetLifecycleCheckpoint? = nil
    ) {
        self.kind = kind
        self.timestamp = timestamp
        self.provider = provider
        self.workspace = workspace
        self.sessionID = sessionID
        self.parentSessionID = parentSessionID
        self.turnID = turnID
        self.toolName = toolName
        self.toolUseID = toolUseID
        self.permissionRequestID = permissionRequestID
        self.lifecycleCheckpoint = lifecycleCheckpoint
        self.hookEventName = hookEventName
        self.assistantSummary = assistantSummary
        self.status = status
    }

    public init?(jsonLine: String) {
        guard
            let data = jsonLine.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let kind = object["event"] as? String,
            let timestamp = Self.timestamp(from: object["timestamp"])
        else {
            return nil
        }

        self.init(
            kind: kind,
            timestamp: timestamp,
            provider: (object["provider"] as? String).flatMap(PetProvider.init(rawValue:)) ?? .codex,
            workspace: object["workspace"] as? String,
            sessionID: object["session_id"] as? String,
            parentSessionID: object["parent_session_id"] as? String,
            turnID: object["turn_id"] as? String,
            toolName: object["tool_name"] as? String,
            hookEventName: object["hook_event_name"] as? String,
            assistantSummary: object["assistant_summary"] as? String,
            status: object["status"] as? String,
            toolUseID: object["tool_use_id"] as? String,
            permissionRequestID: object["permission_request_id"] as? String,
            lifecycleCheckpoint: (object["lifecycle_checkpoint"] as? [String: Any]).flatMap {
                guard let data = try? JSONSerialization.data(withJSONObject: $0) else { return nil }
                return try? JSONDecoder().decode(CodexPetLifecycleCheckpoint.self, from: data)
            }
        )
    }

    enum CodingKeys: String, CodingKey {
        case kind = "event"
        case timestamp, provider, workspace, status
        case sessionID = "session_id"
        case parentSessionID = "parent_session_id"
        case turnID = "turn_id"
        case toolName = "tool_name"
        case toolUseID = "tool_use_id"
        case permissionRequestID = "permission_request_id"
        case hookEventName = "hook_event_name"
        case assistantSummary = "assistant_summary"
        case lifecycleCheckpoint = "lifecycle_checkpoint"
    }

    func withCheckpoint(_ checkpoint: CodexPetLifecycleCheckpoint?, workspaceOverride: String? = nil) -> CodexPetEvent {
        CodexPetEvent(
            kind: kind, timestamp: timestamp, provider: provider, workspace: workspaceOverride ?? workspace,
            sessionID: sessionID, parentSessionID: parentSessionID, turnID: turnID,
            toolName: toolName, hookEventName: hookEventName, assistantSummary: assistantSummary,
            status: status, toolUseID: toolUseID, permissionRequestID: permissionRequestID,
            lifecycleCheckpoint: checkpoint
        )
    }

    private static func timestamp(from value: Any?) -> TimeInterval? {
        if value is Bool {
            return nil
        }
        if let value = value as? TimeInterval {
            return value
        }
        if let value = value as? Int {
            return TimeInterval(value)
        }
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        return nil
    }
}

public struct CodexPetEventLogSnapshot: Equatable, Sendable {
    public let fileSize: UInt64
    public let modificationDate: Date?
    public let backupFileSize: UInt64
    public let backupModificationDate: Date?
    public let events: [CodexPetEvent]

    public init(
        fileSize: UInt64,
        modificationDate: Date?,
        backupFileSize: UInt64 = 0,
        backupModificationDate: Date? = nil,
        events: [CodexPetEvent]
    ) {
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.backupFileSize = backupFileSize
        self.backupModificationDate = backupModificationDate
        self.events = events
    }

    fileprivate func matches(
        fileSize: UInt64,
        modificationDate: Date?,
        backupFileSize: UInt64,
        backupModificationDate: Date?
    ) -> Bool {
        self.fileSize == fileSize
            && self.modificationDate == modificationDate
            && self.backupFileSize == backupFileSize
            && self.backupModificationDate == backupModificationDate
    }
}

public struct CodexPetRetainedEventLog: Equatable, Sendable {
    public let events: [CodexPetEvent]
    /// The byte offset immediately after the last complete line read from the
    /// active log. Incremental readers resume here so an in-flight partial line
    /// is consumed after its terminating newline arrives.
    public let activeReadOffset: UInt64
    public let activeFileSize: UInt64
    public let activeModificationDate: Date?
    public let backupFileSize: UInt64
    public let backupModificationDate: Date?

    public init(
        events: [CodexPetEvent],
        activeReadOffset: UInt64,
        activeFileSize: UInt64,
        activeModificationDate: Date?,
        backupFileSize: UInt64,
        backupModificationDate: Date?
    ) {
        self.events = events
        self.activeReadOffset = activeReadOffset
        self.activeFileSize = activeFileSize
        self.activeModificationDate = activeModificationDate
        self.backupFileSize = backupFileSize
        self.backupModificationDate = backupModificationDate
    }
}

public struct CodexPetActiveScope: Equatable, Identifiable, Sendable {
    public let provider: PetProvider
    public let scopedIdentity: String
    public let activity: CodexActivity
    public let sessionID: String?
    public let parentSessionID: String?
    public let timestamp: TimeInterval?
    public let workspace: String?
    public let turnID: String?
    public let turnStartedAt: TimeInterval?

    public var id: String {
        scopedIdentity
    }

    public init(
        provider: PetProvider,
        scopedIdentity: String,
        activity: CodexActivity,
        sessionID: String? = nil,
        parentSessionID: String? = nil,
        timestamp: TimeInterval? = nil,
        workspace: String? = nil,
        turnID: String? = nil,
        turnStartedAt: TimeInterval? = nil
    ) {
        self.turnID = turnID
        self.turnStartedAt = turnStartedAt
        self.timestamp = timestamp
        self.workspace = workspace
        self.provider = provider
        self.scopedIdentity = scopedIdentity
        self.activity = activity
        self.sessionID = sessionID
        self.parentSessionID = parentSessionID
    }
}

public struct CodexPetActivitySnapshot: Equatable, Sendable {
    public let activity: CodexActivity?
    public let activeSessionIDs: Set<String>
    public let activeScopeCount: Int
    public let activeScopes: [CodexPetActiveScope]

    public init(
        activity: CodexActivity?,
        activeSessionIDs: Set<String>,
        activeScopeCount: Int,
        activeScopes: [CodexPetActiveScope] = []
    ) {
        self.activity = activity
        self.activeSessionIDs = activeSessionIDs
        self.activeScopeCount = activeScopeCount
        self.activeScopes = activeScopes
    }
}

public enum CodexPetEventLog {
    public static func snapshot(
        jsonLines: String,
        now: Date = Date(),
        activeWindow: TimeInterval = 6 * 60 * 60,
        reviewWindow: TimeInterval = 24 * 60 * 60
    ) -> CodexPetActivitySnapshot {
        snapshot(
            from: events(jsonLines: jsonLines),
            now: now,
            activeWindow: activeWindow,
            reviewWindow: reviewWindow
        )
    }

    public static func snapshot(
        events: [CodexPetEvent],
        now: Date = Date(),
        activeWindow: TimeInterval = 6 * 60 * 60,
        reviewWindow: TimeInterval = 24 * 60 * 60
    ) -> CodexPetActivitySnapshot {
        snapshot(
            from: events,
            now: now,
            activeWindow: activeWindow,
            reviewWindow: reviewWindow
        )
    }

    public static func snapshot(
        in url: URL,
        now: Date = Date(),
        activeWindow: TimeInterval = 6 * 60 * 60,
        reviewWindow: TimeInterval = 24 * 60 * 60,
        tailByteLimit: Int = 262_144,
        snapshot: inout CodexPetEventLogSnapshot?
    ) throws -> CodexPetActivitySnapshot {
        // Kept for source compatibility with the earlier single-file tail API.
        // Retained logs are bounded by the hook's rotation policy and must be
        // consumed in full so low-volume provider sessions are not discarded.
        _ = tailByteLimit
        let activeSignature = fileSignatureIfPresent(at: url)
        let backupSignature = fileSignatureIfPresent(at: backupURL(for: url))
        if let snapshot, snapshot.matches(
            fileSize: activeSignature.size,
            modificationDate: activeSignature.modificationDate,
            backupFileSize: backupSignature.size,
            backupModificationDate: backupSignature.modificationDate
        ) {
            return Self.snapshot(
                from: snapshot.events,
                now: now,
                activeWindow: activeWindow,
                reviewWindow: reviewWindow
            )
        }

        let retainedLog = try retainedEvents(from: url)
        snapshot = CodexPetEventLogSnapshot(
            fileSize: retainedLog.activeFileSize,
            modificationDate: retainedLog.activeModificationDate,
            backupFileSize: retainedLog.backupFileSize,
            backupModificationDate: retainedLog.backupModificationDate,
            events: retainedLog.events
        )
        return Self.snapshot(
            from: retainedLog.events,
            now: now,
            activeWindow: activeWindow,
            reviewWindow: reviewWindow
        )
    }

    /// Reads the rotated backup first and the active log second. The hook caps
    /// each retained file at five MiB, so this captures every retained scope
    /// while preserving the chronological order across a rotation boundary.
    public static func retainedEvents(
        from activeURL: URL,
        backupSuffix: String = ".1"
    ) throws -> CodexPetRetainedEventLog {
        let backupURL = URL(fileURLWithPath: activeURL.path + backupSuffix)
        var lastCompletedRead: CodexPetRetainedEventLog?
        var lastError: Error?

        // Rotation replaces the backup and active paths separately. Retry if
        // the backup changes while both files are being opened so the returned
        // sequence cannot skip the just-rotated active log.
        for _ in 0..<3 {
            let backupBefore = fileSignatureIfPresent(at: backupURL)
            do {
                let backup = try readCompleteEventFile(at: backupURL)
                let active = try readCompleteEventFile(at: activeURL)
                let retainedLog = CodexPetRetainedEventLog(
                    events: backup.events + active.events,
                    activeReadOffset: active.readOffset,
                    activeFileSize: active.fileSize,
                    activeModificationDate: active.modificationDate,
                    backupFileSize: backup.fileSize,
                    backupModificationDate: backup.modificationDate
                )
                lastCompletedRead = retainedLog
                let backupAfter = fileSignatureIfPresent(at: backupURL)
                if signaturesMatch(backupBefore, backupAfter) {
                    return retainedLog
                }
            } catch {
                lastError = error
            }
        }

        if lastCompletedRead != nil {
            throw RetainedEventLogReadError.rotationDidNotStabilize
        }
        if let lastError {
            throw lastError
        }
        return CodexPetRetainedEventLog(
            events: [],
            activeReadOffset: 0,
            activeFileSize: 0,
            activeModificationDate: nil,
            backupFileSize: 0,
            backupModificationDate: nil
        )
    }

    private enum RetainedEventLogReadError: Error {
        case rotationDidNotStabilize
    }

    /// Reduces every retained scope to an independent checkpoint. A checkpoint
    /// reserves one slot regardless of event volume; it includes completed turn
    /// identities and unresolved permissions, not merely the last raw callback.
    public static func compactedEvents(
        _ events: [CodexPetEvent],
        now: Date = Date(),
        retentionWindow: TimeInterval,
        maximumCount: Int,
        activeWindow: TimeInterval = 6 * 60 * 60,
        reviewWindow: TimeInterval = 24 * 60 * 60
    ) -> [CodexPetEvent] {
        guard maximumCount > 0 else { return [] }
        let cutoff = now.timeIntervalSince1970 - max(0, retentionWindow)
        var seenEvents = Set<CodexPetEvent>()
        let unique = events.filter { seenEvents.insert($0).inserted }
        if unique.count <= maximumCount, unique.allSatisfy({ $0.timestamp >= cutoff }) { return unique }
        let grouped = Dictionary(grouping: unique.filter(CodexPetLifecycle.isStateBearing), by: ActivityScope.init)
        let checkpoints = grouped.values.compactMap { scopeEvents -> CodexPetEvent? in
            guard let checkpoint = CodexPetLifecycle.checkpoint(
                events: scopeEvents, activeWindow: activeWindow,
                attentionWindow: reviewWindow, retentionCutoff: cutoff, now: now.timeIntervalSince1970
            ), checkpoint.timestamp >= cutoff else { return nil }
            return checkpoint
        }
        return checkpoints.sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp > $1.timestamp }
            return ActivityScope(event: $0).scopedIdentity > ActivityScope(event: $1).scopedIdentity
        }.prefix(maximumCount).reversed()
    }

    public static func activity(
        jsonLines: String,
        now: Date = Date(),
        activeWindow: TimeInterval = 6 * 60 * 60
    ) -> CodexActivity? {
        snapshot(
            jsonLines: jsonLines,
            now: now,
            activeWindow: activeWindow
        ).activity
    }

    public static func activity(
        in url: URL,
        now: Date = Date(),
        activeWindow: TimeInterval = 6 * 60 * 60,
        tailByteLimit: Int = 262_144
    ) throws -> CodexActivity? {
        var snapshot: CodexPetEventLogSnapshot?
        return try activity(
            in: url,
            now: now,
            activeWindow: activeWindow,
            tailByteLimit: tailByteLimit,
            snapshot: &snapshot
        )
    }

    public static func activity(
        in url: URL,
        now: Date = Date(),
        activeWindow: TimeInterval = 6 * 60 * 60,
        tailByteLimit: Int = 262_144,
        snapshot: inout CodexPetEventLogSnapshot?
    ) throws -> CodexActivity? {
        try Self.snapshot(
            in: url,
            now: now,
            activeWindow: activeWindow,
            tailByteLimit: tailByteLimit,
            snapshot: &snapshot
        ).activity
    }

    public static func readEvents(from url: URL, startingAt offset: inout UInt64) throws -> [CodexPetEvent] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            offset = 0
            return []
        }

        let fileSize = try fileSize(at: url)
        if offset > fileSize {
            offset = 0
        }

        let startOffset = offset
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        try handle.seek(toOffset: startOffset)
        guard let data = try handle.readToEnd(), !data.isEmpty else {
            return []
        }

        let completeData = completeLineData(from: data, startOffset: startOffset, offset: &offset)
        guard
            !completeData.isEmpty,
            let text = String(data: completeData, encoding: .utf8)
        else {
            return []
        }

        return events(jsonLines: text)
    }

    private struct ActivityScope: Hashable {
        let provider: PetProvider
        let workspace: String?
        let sessionID: String?
        let fallbackTurnID: String?

        init(event: CodexPetEvent) {
            provider = event.provider
            let normalizedSessionID = Self.nonEmpty(event.sessionID)
            sessionID = normalizedSessionID
            workspace = normalizedSessionID == nil ? Self.nonEmpty(event.workspace) : nil
            fallbackTurnID = normalizedSessionID == nil ? Self.nonEmpty(event.turnID) : nil
        }

        var scopedIdentity: String {
            [
                Self.identityComponent(name: "provider", value: provider.rawValue),
                Self.identityComponent(name: "workspace", value: workspace ?? ""),
                Self.identityComponent(name: "session", value: sessionID ?? ""),
                Self.identityComponent(name: "turn", value: fallbackTurnID ?? ""),
            ]
            .joined(separator: "|")
        }

        private static func nonEmpty(_ value: String?) -> String? {
            guard let value, !value.isEmpty else {
                return nil
            }
            return value
        }

        private static func identityComponent(name: String, value: String) -> String {
            "\(name)=\(value.utf8.count):\(value)"
        }
    }

    private static func snapshot(
        from events: [CodexPetEvent],
        now: Date,
        activeWindow: TimeInterval,
        reviewWindow: TimeInterval = 24 * 60 * 60
    ) -> CodexPetActivitySnapshot {
        var eventsByScope: [ActivityScope: [CodexPetEvent]] = [:]

        for event in events {
            guard CodexPetLifecycle.isStateBearing(event) else {
                continue
            }
            let scope = ActivityScope(event: event)
            eventsByScope[scope, default: []].append(event)
        }

        var activeSessionIDs = Set<String>()
        var activeScopes: [CodexPetActiveScope] = []
        let activeActivities = eventsByScope.compactMap { scope, scopeEvents -> CodexActivity? in
            guard
                let state = CodexPetLifecycle.reduce(
                    events: scopeEvents,
                    activeWindow: activeWindow,
                    attentionWindow: reviewWindow,
                    now: now.timeIntervalSince1970
                ),
                state.isCurrent(
                    at: now.timeIntervalSince1970,
                    activeWindow: activeWindow,
                    attentionWindow: reviewWindow,
                    terminalWindow: activeWindow
                )
            else {
                return nil
            }
            let event = state.event
            let activity = state.activity
            if activity != .idle {
                activeScopes.append(
                    CodexPetActiveScope(
                        provider: event.provider,
                        scopedIdentity: scope.scopedIdentity,
                        activity: activity,
                        sessionID: event.sessionID,
                        parentSessionID: event.parentSessionID,
                        timestamp: event.timestamp,
                        workspace: scopeEvents.sorted { $0.timestamp < $1.timestamp }
                            .first { !($0.workspace?.isEmpty ?? true) }?.workspace ?? event.workspace,
                        turnID: state.currentTurnID,
                        turnStartedAt: state.turnStartedAt
                    )
                )
                if let sessionID = event.sessionID, !sessionID.isEmpty {
                    activeSessionIDs.insert(scopedSessionID(for: event.provider, sessionID: sessionID))
                }
            }
            return activity
        }

        activeScopes.sort { lhs, rhs in
            let lhsProviderOrder = providerOrder(lhs.provider)
            let rhsProviderOrder = providerOrder(rhs.provider)
            if lhsProviderOrder != rhsProviderOrder {
                return lhsProviderOrder < rhsProviderOrder
            }
            return lhs.scopedIdentity < rhs.scopedIdentity
        }

        return CodexPetActivitySnapshot(
            activity: activeActivities.max { priority(for: $0) < priority(for: $1) },
            activeSessionIDs: activeSessionIDs,
            activeScopeCount: activeScopes.count,
            activeScopes: activeScopes
        )
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

    private static func scopedSessionID(for provider: PetProvider, sessionID: String) -> String {
        provider == .codex ? sessionID : "\(provider.rawValue):\(sessionID)"
    }

    private static func events(jsonLines: String) -> [CodexPetEvent] {
        jsonLines
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                CodexPetEvent(jsonLine: String(line))
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

    private struct EventFileContents {
        let events: [CodexPetEvent]
        let readOffset: UInt64
        let fileSize: UInt64
        let modificationDate: Date?
    }

    private static func readCompleteEventFile(at url: URL) throws -> EventFileContents {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return EventFileContents(events: [], readOffset: 0, fileSize: 0, modificationDate: nil)
        }

        let signature = try fileSignature(at: url)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let maximumReadCount = Int(min(signature.size, UInt64(Int.max)))
        let data = try handle.read(upToCount: maximumReadCount) ?? Data()
        var readOffset: UInt64 = 0
        let completeData = completeLineData(from: data, startOffset: 0, offset: &readOffset)
        var parsedEvents: [CodexPetEvent]
        if let text = String(data: completeData, encoding: .utf8) {
            parsedEvents = events(jsonLines: text)
        } else {
            parsedEvents = []
        }
        if readOffset < UInt64(data.count) {
            let trailingStart = data.index(data.startIndex, offsetBy: Int(readOffset))
            let trailingData = data.suffix(from: trailingStart)
            if
                let trailingLine = String(data: trailingData, encoding: .utf8),
                let event = CodexPetEvent(jsonLine: trailingLine)
            {
                parsedEvents.append(event)
                readOffset = UInt64(data.count)
            }
        }

        return EventFileContents(
            events: parsedEvents,
            readOffset: readOffset,
            fileSize: signature.size,
            modificationDate: signature.modificationDate
        )
    }

    private static func backupURL(for activeURL: URL) -> URL {
        URL(fileURLWithPath: activeURL.path + ".1")
    }

    private static func fileSize(at url: URL) throws -> UInt64 {
        try fileSignature(at: url).size
    }

    private static func fileSignatureIfPresent(at url: URL) -> (size: UInt64, modificationDate: Date?) {
        (try? fileSignature(at: url)) ?? (0, nil)
    }

    private static func signaturesMatch(
        _ left: (size: UInt64, modificationDate: Date?),
        _ right: (size: UInt64, modificationDate: Date?)
    ) -> Bool {
        left.size == right.size && left.modificationDate == right.modificationDate
    }

    private static func fileSignature(at url: URL) throws -> (size: UInt64, modificationDate: Date?) {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (
            attributes[.size] as? UInt64 ?? 0,
            attributes[.modificationDate] as? Date
        )
    }

    private static func completeLineData(from data: Data, startOffset: UInt64, offset: inout UInt64) -> Data {
        guard data.last == UInt8(ascii: "\n") else {
            guard let lastNewlineIndex = data.lastIndex(of: UInt8(ascii: "\n")) else {
                offset = startOffset
                return Data()
            }

            let endIndex = data.index(after: lastNewlineIndex)
            offset = startOffset + UInt64(data.distance(from: data.startIndex, to: endIndex))
            return data.prefix(upTo: endIndex)
        }

        offset = startOffset + UInt64(data.count)
        return data
    }

}

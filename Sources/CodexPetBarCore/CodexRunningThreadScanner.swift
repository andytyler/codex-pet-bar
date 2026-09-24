import Darwin
import Foundation

/// A visible local Codex run discovered from rollout metadata. Child runs keep
/// their own session identity while retaining the resumable parent relationship.
public struct CodexRolloutActivityScope: Equatable, Hashable, Sendable {
    public let sessionID: String
    public let parentSessionID: String?
    public let workspace: String?
    public let modificationDate: Date
    public let marker: CodexRunningThreadLog.Marker?

    public init(
        sessionID: String,
        parentSessionID: String? = nil,
        workspace: String? = nil,
        modificationDate: Date = .distantPast,
        marker: CodexRunningThreadLog.Marker? = nil
    ) {
        self.sessionID = sessionID
        self.parentSessionID = parentSessionID
        self.workspace = workspace
        self.modificationDate = modificationDate
        self.marker = marker
    }
}

public struct CodexRunningThreadScan: Equatable, Sendable {
    public let runningScopes: [CodexRolloutActivityScope]
    public let completedScopes: [CodexRolloutActivityScope]

    public var runningThreadIDs: [String] {
        runningScopes.map(\.sessionID)
    }

    public var completedThreadIDs: Set<String> {
        Set(completedScopes.map(\.sessionID))
    }

    public init(runningThreadIDs: [String], completedThreadIDs: Set<String>) {
        self.runningScopes = runningThreadIDs.map { CodexRolloutActivityScope(sessionID: $0) }
        self.completedScopes = completedThreadIDs
            .sorted()
            .map { CodexRolloutActivityScope(sessionID: $0) }
    }

    public init(
        runningScopes: [CodexRolloutActivityScope],
        completedScopes: [CodexRolloutActivityScope]
    ) {
        self.runningScopes = runningScopes
        self.completedScopes = completedScopes
    }
}

public enum CodexRunningThreadScanner {
    /// Discovers every recently-written visible rollout directly from the
    /// sessions tree. Unlike the session-index path, this includes spawned
    /// agents and a resumed parent whose rollout lives in an older day folder.
    ///
    /// Directory traversal reads metadata only. Rollout contents are inspected
    /// with the bounded tail reader after candidates are freshness-filtered.
    /// `limit` is applied independently to running and completed results so a
    /// burst of completions cannot hide an active run.
    public static func activityScan(
        in sessionsDirectoryURL: URL,
        now: Date = Date(),
        staleAfter: TimeInterval = 600,
        retainedCompletionThreadIDs: Set<String> = [],
        limit: Int = 80,
        fileManager: FileManager = .default
    ) -> CodexRunningThreadScan {
        guard limit > 0, staleAfter >= 0 else {
            return CodexRunningThreadScan(runningScopes: [], completedScopes: [])
        }

        let candidates = recentlyModifiedRolloutLogURLs(
            in: sessionsDirectoryURL,
            now: now,
            staleAfter: staleAfter,
            retainingThreadIDs: retainedCompletionThreadIDs,
            fileManager: fileManager
        )

        var seenSessionIDs = Set<String>()
        var runningScopes: [CodexRolloutActivityScope] = []
        var completedScopes: [CodexRolloutActivityScope] = []
        for candidate in candidates {
            guard
                let metadata = rolloutSessionMetadata(from: candidate.url),
                metadata.isVisible,
                !seenSessionIDs.contains(metadata.sessionID)
            else {
                continue
            }

            guard let marker = try? CodexRunningThreadLog.marker(in: candidate.url) else {
                continue
            }
            // A marker-free newer file may be an interrupted resume bootstrap;
            // it must not mask an older rollout with a real lifecycle marker.
            // Once a marker is classified, however, it is authoritative for
            // this session even if its running lease has gone stale.
            seenSessionIDs.insert(metadata.sessionID)
            let scope = CodexRolloutActivityScope(
                sessionID: metadata.sessionID,
                parentSessionID: metadata.parentSessionID,
                workspace: metadata.workspace,
                modificationDate: candidate.modificationDate,
                marker: marker
            )
            let age = now.timeIntervalSince(candidate.modificationDate)
            switch marker.state {
            case .running where age <= staleAfter && runningScopes.count < limit:
                runningScopes.append(scope)
            case .completed where
                (age <= staleAfter || retainedCompletionThreadIDs.contains(metadata.sessionID))
                    && completedScopes.count < limit:
                completedScopes.append(scope)
            case .running, .completed:
                break
            }
            if runningScopes.count == limit, completedScopes.count == limit {
                break
            }
        }

        return CodexRunningThreadScan(
            runningScopes: runningScopes,
            completedScopes: completedScopes
        )
    }

    public static func runningThreadCount(
        in sessionsDirectoryURL: URL,
        now: Date = Date(),
        staleAfter: TimeInterval = 600,
        limit: Int = 80,
        fileManager: FileManager = .default
    ) -> Int {
        runningThreadLogURLs(
            in: sessionsDirectoryURL,
            now: now,
            staleAfter: staleAfter,
            limit: limit,
            fileManager: fileManager
        ).count
    }

    public static func runningThreadCount(
        forThreadIDs threadIDs: [String],
        in sessionsDirectoryURL: URL,
        now: Date = Date(),
        staleAfter: TimeInterval = 600,
        limit: Int = 80,
        fileManager: FileManager = .default
    ) -> Int {
        runningThreadLogURLs(
            forThreadIDs: threadIDs,
            in: sessionsDirectoryURL,
            now: now,
            staleAfter: staleAfter,
            limit: limit,
            fileManager: fileManager
        ).count
    }

    /// Returns only running top-level thread IDs supplied by the caller.
    /// Results are unique and retain the newest-first rollout order.
    public static func runningThreadIDs(
        forThreadIDs threadIDs: [String],
        in sessionsDirectoryURL: URL,
        now: Date = Date(),
        staleAfter: TimeInterval = 600,
        limit: Int = 80,
        fileManager: FileManager = .default
    ) -> [String] {
        activityScan(
            forThreadIDs: threadIDs,
            in: sessionsDirectoryURL,
            now: now,
            staleAfter: staleAfter,
            limit: limit,
            fileManager: fileManager
        ).runningThreadIDs
    }

    /// Classifies only rollout logs with an explicit current marker. Missing,
    /// unreadable, and marker-free logs are intentionally absent so callers
    /// never treat a failed scan as proof that a hook-derived run completed.
    public static func activityScan(
        forThreadIDs threadIDs: [String],
        in sessionsDirectoryURL: URL,
        now: Date = Date(),
        staleAfter: TimeInterval = 600,
        limit: Int = 80,
        fileManager: FileManager = .default
    ) -> CodexRunningThreadScan {
        guard limit > 0 else {
            return CodexRunningThreadScan(runningThreadIDs: [], completedThreadIDs: [])
        }

        let matchingThreadIDs = Set(threadIDs.filter { !$0.isEmpty })
        guard !matchingThreadIDs.isEmpty else {
            return CodexRunningThreadScan(runningThreadIDs: [], completedThreadIDs: [])
        }

        let threadDates = matchingThreadIDs.compactMap(uuidV7Date)
        let scanDates = threadDates + recentWindowDates(now: now, staleAfter: staleAfter)
        let urls = candidateRolloutLogURLs(
            inDayDirectories: sessionDayDirectories(forDates: scanDates, in: sessionsDirectoryURL),
            matchingThreadIDs: matchingThreadIDs,
            now: now,
            // Explicit task completion remains authoritative after the
            // liveness window. Running markers still require a fresh file
            // below, so an abandoned rollout cannot create a phantom flag.
            staleAfter: .infinity,
            fileManager: fileManager
        )

        var seen = Set<String>()
        var runningScopes: [CodexRolloutActivityScope] = []
        var completedScopes: [CodexRolloutActivityScope] = []
        for url in urls {
            guard
                let threadID = matchingThreadID(
                    inRolloutFilename: url.lastPathComponent,
                    matchingThreadIDs: matchingThreadIDs
                ),
                seen.insert(threadID).inserted
            else {
                continue
            }

            guard let marker = try? CodexRunningThreadLog.marker(in: url) else {
                continue
            }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            let scope = CodexRolloutActivityScope(
                sessionID: threadID,
                modificationDate: values?.contentModificationDate ?? .distantPast,
                marker: marker
            )
            switch marker.state {
            case .running:
                guard
                    let modificationDate = values?.contentModificationDate,
                    now.timeIntervalSince(modificationDate) <= staleAfter
                else {
                    continue
                }
                runningScopes.append(scope)
            case .completed:
                completedScopes.append(scope)
            }
            if runningScopes.count + completedScopes.count == limit {
                break
            }
        }
        return CodexRunningThreadScan(
            runningScopes: runningScopes,
            completedScopes: completedScopes
        )
    }

    public static func runningThreadLogURLs(
        in sessionsDirectoryURL: URL,
        now: Date = Date(),
        staleAfter: TimeInterval = 600,
        limit: Int = 80,
        fileManager: FileManager = .default
    ) -> [URL] {
        runningThreadLogURLs(
            inDayDirectories: sessionDayDirectories(
                forDates: recentWindowDates(now: now, staleAfter: staleAfter),
                in: sessionsDirectoryURL
            ),
            matchingThreadIDs: nil,
            now: now,
            staleAfter: staleAfter,
            limit: limit,
            fileManager: fileManager
        )
    }

    public static func runningThreadLogURLs(
        forThreadIDs threadIDs: [String],
        in sessionsDirectoryURL: URL,
        now: Date = Date(),
        staleAfter: TimeInterval = 600,
        limit: Int = 80,
        fileManager: FileManager = .default
    ) -> [URL] {
        let threadIDs = Array(Set(threadIDs.filter { !$0.isEmpty }))
        guard !threadIDs.isEmpty else {
            return []
        }

        let threadDates = threadIDs.compactMap(uuidV7Date)
        let scanDates = threadDates + recentWindowDates(now: now, staleAfter: staleAfter)
        return runningThreadLogURLs(
            inDayDirectories: sessionDayDirectories(forDates: scanDates, in: sessionsDirectoryURL),
            matchingThreadIDs: Set(threadIDs),
            now: now,
            staleAfter: staleAfter,
            limit: limit,
            fileManager: fileManager
        )
    }

    private static func runningThreadLogURLs(
        inDayDirectories dayDirectories: [URL],
        matchingThreadIDs threadIDs: Set<String>?,
        now: Date,
        staleAfter: TimeInterval,
        limit: Int,
        fileManager: FileManager
    ) -> [URL] {
        guard limit > 0 else {
            return []
        }

        return candidateRolloutLogURLs(
            inDayDirectories: dayDirectories,
            matchingThreadIDs: threadIDs,
            now: now,
            staleAfter: staleAfter,
            fileManager: fileManager
        )
        .filter { (try? CodexRunningThreadLog.isRunning(in: $0)) == true }
        .prefix(limit)
        .map { $0 }
    }

    private static func candidateRolloutLogURLs(
        inDayDirectories dayDirectories: [URL],
        matchingThreadIDs threadIDs: Set<String>?,
        now: Date,
        staleAfter: TimeInterval,
        fileManager: FileManager
    ) -> [URL] {
        var candidates: [(url: URL, modificationDate: Date)] = []
        for directory in dayDirectories {
            let urls = (try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for url in urls {
                guard
                    url.pathExtension == "jsonl",
                    url.lastPathComponent.hasPrefix("rollout-"),
                    rolloutLogFilename(url.lastPathComponent, matchesThreadIDs: threadIDs)
                else {
                    continue
                }

                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard
                    values?.isRegularFile == true,
                    let modificationDate = values?.contentModificationDate,
                    now.timeIntervalSince(modificationDate) <= staleAfter
                else {
                    continue
                }

                candidates.append((url, modificationDate))
            }
        }

        return candidates
            .sorted { $0.modificationDate > $1.modificationDate }
            .map(\.url)
    }

    private static func recentlyModifiedRolloutLogURLs(
        in sessionsDirectoryURL: URL,
        now: Date,
        staleAfter: TimeInterval,
        retainingThreadIDs: Set<String>,
        fileManager: FileManager
    ) -> [(url: URL, modificationDate: Date)] {
        var candidates: [(url: URL, modificationDate: Date)] = []
        let rootPath = sessionsDirectoryURL.path
        for year in directoryNames(atPath: rootPath, fileManager: fileManager)
        where isNumericPathComponent(year, length: 4) {
            let yearPath = rootPath + "/" + year
            for month in directoryNames(atPath: yearPath, fileManager: fileManager)
            where isNumericPathComponent(month, length: 2) {
                let monthPath = yearPath + "/" + month
                for day in directoryNames(atPath: monthPath, fileManager: fileManager)
                where isNumericPathComponent(day, length: 2) {
                    let dayPath = monthPath + "/" + day
                    for filename in directoryNames(atPath: dayPath, fileManager: fileManager) {
                        guard filename.hasPrefix("rollout-"), filename.hasSuffix(".jsonl") else {
                            continue
                        }

                        let path = dayPath + "/" + filename
                        var attributes = stat()
                        guard
                            lstat(path, &attributes) == 0,
                            attributes.st_mode & S_IFMT == S_IFREG
                        else {
                            continue
                        }
                        let modificationDate = Date(
                            timeIntervalSince1970: TimeInterval(attributes.st_mtimespec.tv_sec)
                                + (TimeInterval(attributes.st_mtimespec.tv_nsec) / 1_000_000_000)
                        )
                        let isFresh = now.timeIntervalSince(modificationDate) <= staleAfter
                        let isRetainedTarget = retainingThreadIDs.contains { threadID in
                            filename.hasSuffix("-\(threadID).jsonl")
                        }
                        guard isFresh || isRetainedTarget else {
                            continue
                        }
                        candidates.append((URL(fileURLWithPath: path), modificationDate))
                    }
                }
            }
        }

        return candidates.sorted { left, right in
            if left.modificationDate != right.modificationDate {
                return left.modificationDate > right.modificationDate
            }
            return left.url.path > right.url.path
        }
    }

    private static func directoryNames(atPath path: String, fileManager: FileManager) -> [String] {
        ((try? fileManager.contentsOfDirectory(atPath: path)) ?? [])
            .filter { !$0.hasPrefix(".") }
    }

    private static func isNumericPathComponent(_ value: String, length: Int) -> Bool {
        value.utf8.count == length && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func rolloutSessionMetadata(from url: URL) -> RolloutSessionMetadata? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer {
            try? handle.close()
        }
        guard let head = try? handle.read(upToCount: 262_144) else {
            return nil
        }
        guard !head.isEmpty else {
            return nil
        }

        let firstLine: Data
        if let newline = head.firstIndex(of: UInt8(ascii: "\n")) {
            firstLine = head[..<newline]
        } else {
            firstLine = head
        }
        guard
            let object = try? JSONSerialization.jsonObject(with: firstLine) as? [String: Any],
            object["type"] as? String == "session_meta",
            let payload = object["payload"] as? [String: Any],
            let sessionID = nonEmpty(payload["id"] as? String)
        else {
            return nil
        }

        let source = payload["source"] as? [String: Any]
        let subagent = source?["subagent"] as? [String: Any]
        let threadSpawn = subagent?["thread_spawn"] as? [String: Any]
        let parentSessionID = nonEmpty(threadSpawn?["parent_thread_id"] as? String)
        // `subagent.other` currently identifies internal guardian processes,
        // not a user-visible run. Unknown top-level sources remain visible so
        // new Codex surfaces do not silently disappear.
        let isVisible = subagent == nil || threadSpawn != nil

        return RolloutSessionMetadata(
            sessionID: sessionID,
            parentSessionID: parentSessionID,
            workspace: nonEmpty(payload["cwd"] as? String),
            isVisible: isVisible
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func rolloutLogFilename(_ filename: String, matchesThreadIDs threadIDs: Set<String>?) -> Bool {
        guard let threadIDs else {
            return true
        }

        return matchingThreadID(inRolloutFilename: filename, matchingThreadIDs: threadIDs) != nil
    }

    private static func matchingThreadID(
        inRolloutFilename filename: String,
        matchingThreadIDs threadIDs: Set<String>
    ) -> String? {
        guard filename.hasPrefix("rollout-"), filename.hasSuffix(".jsonl") else {
            return nil
        }

        // Prefer the longest exact suffix if callers ever provide overlapping
        // synthetic IDs; real top-level IDs are fixed-width UUIDs.
        return threadIDs
            .filter { filename.hasSuffix("-\($0).jsonl") }
            .max { left, right in left.count < right.count }
    }

    private static func recentWindowDates(now: Date, staleAfter: TimeInterval) -> [Date] {
        let start = now.addingTimeInterval(-max(0, staleAfter))
        var dates = [start, now]
        var cursor = start
        while cursor < now {
            guard let next = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = next
            if cursor < now {
                dates.append(cursor)
            }
        }
        return dates
    }

    private static func sessionDayDirectories(forDates dates: [Date], in sessionsDirectoryURL: URL) -> [URL] {
        var calendars: [Calendar] = {
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
            return [utc, .current]
        }()

        if calendars[0].timeZone == calendars[1].timeZone {
            calendars.removeLast()
        }

        var seen = Set<String>()
        var directories: [URL] = []

        for date in dates {
            for calendar in calendars {
                for dayOffset in -1...1 {
                    guard
                        let adjustedDate = calendar.date(byAdding: .day, value: dayOffset, to: date),
                        let directory = sessionDayDirectory(for: adjustedDate, calendar: calendar, in: sessionsDirectoryURL)
                    else {
                        continue
                    }

                    let key = directory.path
                    if seen.insert(key).inserted {
                        directories.append(directory)
                    }
                }
            }
        }

        return directories
    }

    private static func sessionDayDirectory(for date: Date, calendar: Calendar, in sessionsDirectoryURL: URL) -> URL? {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return nil
        }

        return sessionsDirectoryURL
            .appendingPathComponent(String(format: "%04d", year), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", month), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", day), isDirectory: true)
    }

    private static func uuidV7Date(from id: String) -> Date? {
        let hex = id.filter { $0 != "-" }
        guard
            hex.count >= 12,
            let milliseconds = UInt64(String(hex.prefix(12)), radix: 16)
        else {
            return nil
        }

        return Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }

    private struct RolloutSessionMetadata {
        let sessionID: String
        let parentSessionID: String?
        let workspace: String?
        let isVisible: Bool
    }
}

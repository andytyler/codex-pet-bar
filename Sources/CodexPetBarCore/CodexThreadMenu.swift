import Foundation

public struct CodexThreadSummary: Equatable, Sendable {
    public let id: String
    public let title: String
    public let updatedAt: Date?
    public let folderTitle: String

    public init(id: String, title: String, updatedAt: Date?, folderTitle: String = CodexThreadMenuRows.defaultFolderTitle) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
        self.folderTitle = folderTitle
    }
}

public struct CodexThreadMenuRow: Equatable, Sendable {
    public let id: String
    public let title: String
    public let folderTitle: String
    public let deepLinkURL: URL

    public init(
        id: String,
        title: String,
        folderTitle: String = CodexThreadMenuRows.defaultFolderTitle,
        deepLinkURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.folderTitle = folderTitle
        self.deepLinkURL = deepLinkURL ?? CodexThreadDeepLink.url(forThreadID: id)
    }
}

public enum CodexThreadDeepLink {
    public static func url(forThreadID id: String) -> URL {
        var allowedCharacters = CharacterSet.urlPathAllowed
        allowedCharacters.remove(charactersIn: "/?#")
        let encodedID = id.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? id
        return URL(string: "codex://threads/\(encodedID)")!
    }
}

public struct CodexThreadMenuSection: Equatable, Sendable {
    public let folderTitle: String
    public let rows: [CodexThreadMenuRow]

    public init(folderTitle: String, rows: [CodexThreadMenuRow]) {
        self.folderTitle = folderTitle
        self.rows = rows
    }
}

public enum CodexThreadMenuEntry: Equatable, Sendable {
    case sectionHeader(String)
    case thread(CodexThreadMenuRow)
    case more([CodexThreadMenuRow])
}

public enum CodexSessionIndexLog {
    public static func readRecentThreads(
        from url: URL,
        limit: Int = 12,
        tailByteLimit: Int = 1_048_576
    ) -> [CodexThreadSummary] {
        guard
            let data = try? tailData(from: url, byteLimit: tailByteLimit),
            let text = String(data: data, encoding: .utf8)
        else {
            return []
        }
        return recentThreads(jsonLines: text, limit: limit)
    }

    public static func recentThreads(jsonLines: String, limit: Int = 12) -> [CodexThreadSummary] {
        var latestByID: [String: CodexThreadSummary] = [:]

        for line in jsonLines.split(whereSeparator: \.isNewline) {
            guard let thread = CodexThreadSummary(jsonLine: String(line)) else {
                continue
            }
            if
                let current = latestByID[thread.id],
                (current.updatedAt ?? .distantPast) > (thread.updatedAt ?? .distantPast)
            {
                continue
            }
            latestByID[thread.id] = thread
        }

        let sorted = latestByID.values.sorted { left, right in
            (left.updatedAt ?? .distantPast) > (right.updatedAt ?? .distantPast)
        }

        return Array(sorted.prefix(max(0, limit)))
    }

    private static func tailData(from url: URL, byteLimit: Int) throws -> Data {
        guard byteLimit > 0 else {
            return Data()
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        let size = try handle.seekToEnd()
        let limit = UInt64(byteLimit)
        let startOffset = size > limit ? size - limit : 0
        try handle.seek(toOffset: startOffset)
        let data = try handle.readToEnd() ?? Data()

        guard startOffset > 0, let firstNewlineIndex = data.firstIndex(of: UInt8(ascii: "\n")) else {
            return data
        }

        return data.suffix(from: data.index(after: firstNewlineIndex))
    }
}

public enum CodexThreadMenuRows {
    public static let defaultFolderTitle = "Other"

    public static func build(threads: [CodexThreadSummary]) -> [CodexThreadMenuRow] {
        threads.map { thread in
            CodexThreadMenuRow(
                id: thread.id,
                title: thread.title,
                folderTitle: normalizedFolderTitle(thread.folderTitle)
            )
        }
    }

    public static func normalizedFolderTitle(_ title: String) -> String {
        let normalized = title
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        return normalized.isEmpty ? defaultFolderTitle : normalized
    }
}

public enum CodexThreadMenuSections {
    public static func build(rows: [CodexThreadMenuRow]) -> [CodexThreadMenuSection] {
        var sections: [CodexThreadMenuSection] = []
        var indexesByFolderTitle: [String: Int] = [:]

        for row in rows {
            let folderTitle = CodexThreadMenuRows.normalizedFolderTitle(row.folderTitle)
            if let index = indexesByFolderTitle[folderTitle] {
                var section = sections[index]
                section = CodexThreadMenuSection(folderTitle: section.folderTitle, rows: section.rows + [row])
                sections[index] = section
            } else {
                indexesByFolderTitle[folderTitle] = sections.count
                sections.append(CodexThreadMenuSection(folderTitle: folderTitle, rows: [row]))
            }
        }

        return sections
    }
}

public enum CodexThreadMenuEntries {
    public static func build(
        rows: [CodexThreadMenuRow],
        runningThreadIDs: Set<String>,
        visibleRecentLimit: Int = 3
    ) -> [CodexThreadMenuEntry] {
        var entries: [CodexThreadMenuEntry] = []

        let runningRows = rows.filter { runningThreadIDs.contains($0.id) }
        if !runningRows.isEmpty {
            entries.append(.sectionHeader("Running"))
            entries.append(contentsOf: runningRows.map(CodexThreadMenuEntry.thread))
        }

        let recentRows = rows.filter { !runningThreadIDs.contains($0.id) }
        guard !recentRows.isEmpty else {
            return entries
        }

        entries.append(.sectionHeader("Recent"))
        let visibleCount = max(0, visibleRecentLimit)
        entries.append(contentsOf: recentRows.prefix(visibleCount).map(CodexThreadMenuEntry.thread))

        let overflowRows = Array(recentRows.dropFirst(visibleCount))
        if !overflowRows.isEmpty {
            entries.append(.more(overflowRows))
        }

        return entries
    }
}

private extension CodexThreadSummary {
    init?(jsonLine: String) {
        guard
            let data = jsonLine.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = object["id"] as? String,
            !id.isEmpty
        else {
            return nil
        }

        let rawTitle = object["thread_name"] as? String
        self.init(
            id: id,
            title: Self.displayTitle(from: rawTitle, fallbackID: id),
            updatedAt: Self.date(from: object["updated_at"] as? String),
            folderTitle: CodexThreadMenuRows.defaultFolderTitle
        )
    }

    static func displayTitle(from rawTitle: String?, fallbackID: String) -> String {
        let normalized = (rawTitle ?? "")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        let fallback = "Thread \(fallbackID.prefix(8))"
        let title = normalized.isEmpty ? fallback : normalized
        guard title.count > 70 else {
            return title
        }

        let endIndex = title.index(title.startIndex, offsetBy: 67)
        return String(title[..<endIndex]) + "..."
    }

    static func date(from rawValue: String?) -> Date? {
        guard let rawValue else {
            return nil
        }

        return ISO8601DateFormatter.codexDate(from: rawValue)
    }
}

extension ISO8601DateFormatter {
    static func codexDate(from rawValue: String) -> Date? {
        codexDateFormatterLock.lock()
        defer { codexDateFormatterLock.unlock() }
        return cachedCodexInternetDateTimeWithFractionalSeconds.date(from: rawValue)
            ?? cachedCodexInternetDateTime.date(from: rawValue)
    }

    static var codexInternetDateTimeWithFractionalSeconds: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static let codexDateFormatterLock = NSLock()

    nonisolated(unsafe) private static let cachedCodexInternetDateTimeWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let cachedCodexInternetDateTime: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

public extension ISO8601DateFormatter {
    static var codexSessionIndex: ISO8601DateFormatter {
        codexInternetDateTimeWithFractionalSeconds
    }
}

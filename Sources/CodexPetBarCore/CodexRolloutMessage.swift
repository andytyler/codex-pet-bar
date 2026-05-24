import Foundation

public struct CodexRolloutMessage: Equatable, Sendable {
    public static let maxTextLength = 180

    public let timestamp: Date?
    public let text: String

    public init(timestamp: Date?, text: String) {
        self.timestamp = timestamp
        self.text = text
    }

    public init?(jsonLine: String) {
        guard
            let data = jsonLine.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = object["type"] as? String,
            let payload = object["payload"] as? [String: Any]
        else {
            return nil
        }

        let rawText: String?
        switch type {
        case "event_msg":
            rawText = Self.eventMessageText(from: payload)
        case "response_item":
            rawText = Self.responseItemText(from: payload)
        default:
            rawText = nil
        }

        guard
            let rawText,
            let text = Self.normalizedDisplayText(rawText)
        else {
            return nil
        }

        self.init(
            timestamp: Self.timestamp(from: object["timestamp"] as? String),
            text: text
        )
    }

    private static func eventMessageText(from payload: [String: Any]) -> String? {
        guard
            payload["type"] as? String == "agent_message",
            let message = payload["message"] as? String
        else {
            return nil
        }
        return message
    }

    private static func responseItemText(from payload: [String: Any]) -> String? {
        guard
            payload["type"] as? String == "message",
            payload["role"] as? String == "assistant",
            let content = payload["content"] as? [[String: Any]]
        else {
            return nil
        }

        let text = content.compactMap { item -> String? in
            guard
                item["type"] as? String == "output_text",
                let text = item["text"] as? String
            else {
                return nil
            }
            return text
        }
        .joined(separator: " ")

        return text.isEmpty ? nil : text
    }

    private static func normalizedDisplayText(_ text: String) -> String? {
        let normalized = text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        guard !normalized.isEmpty else {
            return nil
        }

        guard normalized.count > maxTextLength else {
            return normalized
        }

        let endIndex = normalized.index(normalized.startIndex, offsetBy: maxTextLength - 3)
        return String(normalized[..<endIndex]) + "..."
    }

    private static func timestamp(from rawValue: String?) -> Date? {
        guard let rawValue else {
            return nil
        }
        return ISO8601DateFormatter.codexRollout.date(from: rawValue)
    }
}

public enum CodexRolloutMessageLog {
    public static func readMessages(from url: URL, startingAt offset: inout UInt64) throws -> [CodexRolloutMessage] {
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

        return deduplicated(
            text
                .split(whereSeparator: \.isNewline)
                .compactMap { line in
                    CodexRolloutMessage(jsonLine: String(line))
                }
        )
    }

    private static func deduplicated(_ messages: [CodexRolloutMessage]) -> [CodexRolloutMessage] {
        var seen = Set<String>()
        return messages.filter { message in
            seen.insert(message.text).inserted
        }
    }

    private static func fileSize(at url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? UInt64 ?? 0
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

public extension ISO8601DateFormatter {
    static var codexRollout: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

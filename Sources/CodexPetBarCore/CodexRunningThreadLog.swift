import Foundation

public enum CodexRunningThreadLog {
    public enum State: Equatable, Hashable, Sendable {
        case running
        case completed
    }

    public enum CompletionOutcome: Equatable, Hashable, Sendable {
        case success
        case cancelled
    }

    /// The actual lifecycle record, independent of later file modification.
    public struct Marker: Equatable, Hashable, Sendable {
        public let state: State
        public let completionOutcome: CompletionOutcome?
        public let turnID: String?
        public let timestamp: TimeInterval?

        public init(
            state: State,
            completionOutcome: CompletionOutcome? = nil,
            turnID: String? = nil,
            timestamp: TimeInterval? = nil
        ) {
            self.state = state
            self.completionOutcome = completionOutcome
            self.turnID = turnID.flatMap { $0.isEmpty ? nil : $0 }
            self.timestamp = timestamp.flatMap { $0.isFinite ? $0 : nil }
        }

        /// Shared turn identities deduplicate hook and rollout completion.
        /// A timestamp identifies a terminal record when a rollout omits its ID.
        public var terminalIdentity: String? {
            guard state == .completed else { return nil }
            if let turnID { return "turn:\(turnID)" }
            return timestamp.map { "time:\($0)" }
        }
    }

    public static func isRunning(jsonLines: String) -> Bool {
        state(jsonLines: jsonLines) == .running
    }

    public static func state(jsonLines: String) -> State? {
        marker(jsonLines: jsonLines)?.state
    }

    public static func marker(jsonLines: String) -> Marker? {
        latestMarker(jsonLines: jsonLines)
    }

    public static func isRunning(
        in url: URL,
        tailByteLimit: Int = 262_144,
        maximumTailByteLimit: Int = 4_194_304
    ) throws -> Bool {
        try state(
            in: url,
            tailByteLimit: tailByteLimit,
            maximumTailByteLimit: maximumTailByteLimit
        ) == .running
    }

    public static func state(
        in url: URL,
        tailByteLimit: Int = 262_144,
        maximumTailByteLimit: Int = 4_194_304
    ) throws -> State? {
        try marker(
            in: url,
            tailByteLimit: tailByteLimit,
            maximumTailByteLimit: maximumTailByteLimit
        )?.state
    }

    public static func marker(
        in url: URL,
        tailByteLimit: Int = 262_144,
        maximumTailByteLimit: Int = 4_194_304
    ) throws -> Marker? {
        guard tailByteLimit > 0, maximumTailByteLimit > 0 else {
            return nil
        }

        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64 ?? 0
        var byteLimit = min(tailByteLimit, maximumTailByteLimit)
        while true {
            let data = try tailData(from: url, byteLimit: byteLimit)
            if
                let text = String(data: data, encoding: .utf8),
                let marker = latestMarker(jsonLines: text)
            {
                return marker
            }

            guard UInt64(byteLimit) < fileSize, byteLimit < maximumTailByteLimit else {
                return nil
            }
            byteLimit = byteLimit > maximumTailByteLimit / 2
                ? maximumTailByteLimit
                : byteLimit * 2
        }
    }

    private static func latestMarker(jsonLines: String) -> Marker? {
        var latestObject: [String: Any]?
        var latestState: State?

        for line in jsonLines.split(whereSeparator: \.isNewline) {
            guard
                let data = String(line).data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let state = state(from: object)
            else {
                continue
            }

            latestObject = object
            latestState = state
        }
        guard let object = latestObject, let state = latestState,
              let payload = object["payload"] as? [String: Any] else { return nil }
        let eventType = payload["type"] as? String
        let outcome: CompletionOutcome? = switch eventType {
        case "task_complete": .success
        case "turn_aborted": .cancelled
        default: nil
        }
        let turnID = payload["turn_id"] as? String
            ?? ((eventType == "task_complete" || eventType == "task_started") ? payload["id"] as? String : nil)
        // Parse only the final classified record, not every line in a large tail.
        return Marker(
            state: state,
            completionOutcome: outcome,
            turnID: turnID,
            timestamp: timestamp(from: object["timestamp"])
        )
    }

    private static func state(from object: [String: Any]) -> State? {
        guard
            let type = object["type"] as? String,
            let payload = object["payload"] as? [String: Any]
        else {
            return nil
        }

        if type == "event_msg" {
            return eventMarker(from: payload)
        }

        if type == "response_item" {
            return responseItemMarker(from: payload)
        }

        return nil
    }

    private static func timestamp(from value: Any?) -> TimeInterval? {
        if value is Bool { return nil }
        if let number = value as? NSNumber { return number.doubleValue }
        guard let string = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date.timeIntervalSince1970 }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)?.timeIntervalSince1970
    }

    private static func eventMarker(from payload: [String: Any]) -> State? {
        switch payload["type"] as? String {
        case "task_complete", "turn_aborted":
            return .completed
        case "task_started", "user_message", "agent_message", "patch_apply_begin", "patch_apply_end":
            return .running
        default:
            return nil
        }
    }

    private static func responseItemMarker(from payload: [String: Any]) -> State? {
        switch payload["type"] as? String {
        case "function_call", "custom_tool_call", "tool_search_call":
            return .running
        case "message":
            return payload["role"] as? String == "assistant" ? .running : nil
        default:
            return nil
        }
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
        // Include the byte immediately before the requested tail so an exact
        // line-boundary start can be distinguished from a partial first line.
        let readOffset = startOffset > 0 ? startOffset - 1 : 0
        try handle.seek(toOffset: readOffset)
        let data = try handle.readToEnd() ?? Data()

        guard startOffset > 0 else {
            return data
        }

        if data.first == UInt8(ascii: "\n") {
            return data.dropFirst()
        }

        guard let firstNewlineIndex = data.firstIndex(of: UInt8(ascii: "\n")) else {
            return Data()
        }

        return data.suffix(from: data.index(after: firstNewlineIndex))
    }
}

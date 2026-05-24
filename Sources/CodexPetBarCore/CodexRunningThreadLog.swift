import Foundation

public enum CodexRunningThreadLog {
    public static func isRunning(jsonLines: String) -> Bool {
        var latestMarker: ThreadMarker?

        for line in jsonLines.split(whereSeparator: \.isNewline) {
            guard
                let data = String(line).data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let marker = marker(from: object)
            else {
                continue
            }

            latestMarker = marker
        }

        return latestMarker == .running
    }

    public static func isRunning(in url: URL, tailByteLimit: Int = 262_144) throws -> Bool {
        let data = try tailData(from: url, byteLimit: tailByteLimit)
        guard let text = String(data: data, encoding: .utf8) else {
            return false
        }
        return isRunning(jsonLines: text)
    }

    private enum ThreadMarker {
        case running
        case completed
    }

    private static func marker(from object: [String: Any]) -> ThreadMarker? {
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

    private static func eventMarker(from payload: [String: Any]) -> ThreadMarker? {
        switch payload["type"] as? String {
        case "task_complete":
            return .completed
        case "user_message", "agent_message", "patch_apply_begin", "patch_apply_end":
            return .running
        default:
            return nil
        }
    }

    private static func responseItemMarker(from payload: [String: Any]) -> ThreadMarker? {
        switch payload["type"] as? String {
        case "function_call", "custom_tool_call":
            return .running
        case "message":
            return payload["role"] as? String == "assistant" ? .running : nil
        default:
            return nil
        }
    }

    private static func tailData(from url: URL, byteLimit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        let size = try handle.seekToEnd()
        let startOffset = size > UInt64(byteLimit) ? size - UInt64(byteLimit) : 0
        try handle.seek(toOffset: startOffset)
        let data = try handle.readToEnd() ?? Data()

        guard startOffset > 0, let firstNewlineIndex = data.firstIndex(of: UInt8(ascii: "\n")) else {
            return data
        }

        return data.suffix(from: data.index(after: firstNewlineIndex))
    }
}

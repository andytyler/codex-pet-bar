import Foundation

public enum CodexEnvironment {
    public static func homeDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userHomeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    ) -> URL {
        guard
            let configuredValue = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            !configuredValue.isEmpty
        else {
            return userHomeDirectory.appendingPathComponent(".codex", isDirectory: true).standardizedFileURL
        }

        if configuredValue == "~" {
            return userHomeDirectory.standardizedFileURL
        }
        if configuredValue.hasPrefix("~/") {
            return userHomeDirectory
                .appendingPathComponent(String(configuredValue.dropFirst(2)), isDirectory: true)
                .standardizedFileURL
        }
        if configuredValue.hasPrefix("/") {
            return URL(fileURLWithPath: configuredValue, isDirectory: true).standardizedFileURL
        }
        return currentDirectory
            .appendingPathComponent(configuredValue, isDirectory: true)
            .standardizedFileURL
    }
}

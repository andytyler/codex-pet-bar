import AppKit

/// Opens the destination represented by a task without silently changing apps.
/// A successful callback means macOS accepted the open request.
@MainActor
enum PetTaskNavigator {
    static func open(_ task: PetTaskPresentation, completion: @escaping (String?) -> Void) {
        switch task.provider {
        case .codex:
            guard let url = task.deepLinkURL, url.scheme?.lowercased() == "codex" else {
                completion("This task has no Codex link. Open Codex to find it.")
                return
            }
            completion(NSWorkspace.shared.open(url)
                ? nil : "Codex couldn’t open this task. Open Codex and try again.")

        case .cursor:
            guard let projectURL = existingProjectURL(for: task) else {
                completion("This project folder is unavailable. Open the project in Cursor to locate it.")
                return
            }
            guard let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.todesktop.230313mzl4w4u92"
            ), isExistingDirectory(applicationURL) else {
                completion("Open project is unavailable because Cursor isn’t installed. Install Cursor, then try again.")
                return
            }
            let reply = NavigationCompletion(completion)
            NSWorkspace.shared.open(
                [projectURL],
                withApplicationAt: applicationURL,
                configuration: NSWorkspace.OpenConfiguration()
            ) { application, error in
                let succeeded = application != nil && error == nil
                Task { @MainActor in
                    reply.finish(succeeded
                        ? nil : "Cursor couldn’t open this project. Open Cursor and try again.")
                }
            }

        case .claude:
            guard let projectURL = existingProjectURL(for: task) else {
                completion("This project folder is unavailable. Open Claude Code to locate the project.")
                return
            }
            if let url = claudeCodeURL(for: task, projectURL: projectURL) {
                completion(NSWorkspace.shared.open(url)
                    ? nil : "Claude Code couldn’t open this session. Open Claude Code and try again.")
            } else {
                openProjectInFinder(projectURL, completion: completion)
            }

        case .other:
            guard let projectURL = existingProjectURL(for: task) else {
                completion("This project folder is unavailable. Open the project in its agent to locate it.")
                return
            }
            openProjectInFinder(projectURL, completion: completion)
        }
    }

    /// Use the same destination decision for visible row labels and navigation.
    static func actionLabel(for task: PetTaskPresentation) -> String {
        switch task.provider {
        case .codex:
            "Open task in Codex"
        case .cursor:
            "Open project in Cursor"
        case .claude:
            if let projectURL = existingProjectURL(for: task),
               claudeCodeURL(for: task, projectURL: projectURL) != nil {
                "Open session in Claude Code"
            } else {
                "Open project in Finder"
            }
        case .other:
            "Open project in Finder"
        }
    }

    private static func existingProjectURL(for task: PetTaskPresentation) -> URL? {
        guard let url = task.projectURL, isExistingDirectory(url) else { return nil }
        return url
    }

    private static func isExistingDirectory(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private static func claudeCodeURL(for task: PetTaskPresentation, projectURL: URL) -> URL? {
        let sessionID = (task.navigationSourceID ?? task.sourceID)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionID.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "claude-cli"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "cwd", value: projectURL.path),
            URLQueryItem(name: "q", value: "/resume \(sessionID)"),
        ]
        guard let url = components.url,
              NSWorkspace.shared.urlForApplication(toOpen: url) != nil else { return nil }
        return url
    }

    private static func openProjectInFinder(_ projectURL: URL, completion: @escaping (String?) -> Void) {
        guard let finderURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder"),
              isExistingDirectory(finderURL) else {
            completion("Finder is unavailable. Open the project folder manually, then try again.")
            return
        }
        let reply = NavigationCompletion(completion)
        NSWorkspace.shared.open(
            [projectURL],
            withApplicationAt: finderURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { application, error in
            let succeeded = application != nil && error == nil
            Task { @MainActor in
                reply.finish(succeeded
                    ? nil : "Finder couldn’t open this project folder. Check that the folder is still available.")
            }
        }
    }

    /// Keeps the non-Sendable UI callback isolated while AppKit replies asynchronously.
    @MainActor
    private final class NavigationCompletion {
        private var handler: ((String?) -> Void)?

        init(_ handler: @escaping (String?) -> Void) {
            self.handler = handler
        }

        func finish(_ error: String?) {
            let handler = self.handler
            self.handler = nil
            handler?(error)
        }
    }
}

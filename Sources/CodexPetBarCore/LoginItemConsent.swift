import Foundation

public enum LoginItemStatus: Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case unavailable
}

@MainActor
public protocol LoginItemService: AnyObject {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

/// Consent is persisted independently of the system's actual registration state.
/// Declining or a failed registration must not cause a prompt on every launch.
@MainActor
public final class LoginItemConsent {
    private let defaults: UserDefaults
    private let service: any LoginItemService
    public let registrationAllowed: Bool
    private static let askedKey = "hasAskedToOpenAtLogin"

    public init(defaults: UserDefaults, service: any LoginItemService, registrationAllowed: Bool) {
        self.defaults = defaults
        self.service = service
        self.registrationAllowed = registrationAllowed
    }

    public var status: LoginItemStatus { service.status }
    public var hasAsked: Bool { defaults.bool(forKey: Self.askedKey) }
    public var shouldPrompt: Bool {
        guard registrationAllowed && !hasAsked else { return false }
        // macOS can return notFound before this installed main app has ever
        // registered. That does not represent a user choice. Ask for consent
        // once; an accepted registration still reports any system error.
        return status == .notRegistered || status == .unavailable
    }

    public func respondToPrompt(allow: Bool) throws {
        guard registrationAllowed else { return }
        defaults.set(true, forKey: Self.askedKey)
        if allow { try setEnabled(true) }
    }

    public func setEnabled(_ enabled: Bool) throws {
        guard registrationAllowed else { return }
        defaults.set(true, forKey: Self.askedKey)
        if enabled {
            if status != .enabled && status != .requiresApproval { try service.register() }
        } else if status == .enabled || status == .requiresApproval {
            try service.unregister()
        }
    }

    public static func registrationAllowed(
        bundleURL: URL,
        bundleIdentifier: String?,
        arguments: [String],
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        guard bundleIdentifier == "dev.ajt.CodexPetBar",
              !arguments.contains(where: { $0.hasPrefix("--render-") || $0.hasPrefix("--preview-") })
        else { return false }
        let installedURLs = [
            URL(fileURLWithPath: "/Applications/CodexPetBar.app", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications/CodexPetBar.app", isDirectory: true),
        ]
        let current = bundleURL.standardizedFileURL.resolvingSymlinksInPath()
        return installedURLs.contains { $0.standardizedFileURL.resolvingSymlinksInPath() == current }
    }
}

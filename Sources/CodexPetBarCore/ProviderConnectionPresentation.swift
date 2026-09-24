import Foundation

public enum ProviderConnectionAction: String, Equatable, Sendable {
    case connect = "Connect"
    case repair = "Repair"
    case reconnect = "Reconnect"

    public var title: String { rawValue }
}

public enum ProviderConnectionTone: Equatable, Sendable {
    case neutral
    case positive
    case attention
}

/// User-facing connection state is distinct from live task activity. A verified
/// hook can be connected while its agent has no active tasks.
public struct ProviderConnectionPresentation: Equatable, Sendable {
    public let provider: PetProvider
    public let providerName: String
    public let label: String
    public let detail: String
    public let tone: ProviderConnectionTone
    public let action: ProviderConnectionAction?

    public init(health: ProviderIntegrationHealth) {
        provider = health.provider
        providerName = Self.name(for: health.provider)

        switch health.state {
        case .notInstalled:
            label = "Optional"
            detail = health.provider == .codex
                ? "Add richer reactions to Codex activity."
                : "Connect to show this agent’s tasks."
            tone = .neutral
            action = .connect
        case .needsUpdate:
            label = "Needs repair"
            detail = "Activity hooks need updating."
            tone = .attention
            action = .repair
        case .deliveryError:
            label = "Needs attention"
            tone = .attention
            if health.hookRuntimeAvailable {
                detail = "Local activity couldn’t be delivered."
                action = .reconnect
            } else {
                detail = "Python is unavailable. Install Apple’s Command Line Tools."
                action = nil
            }
        case .noSignal:
            label = "Ready"
            detail = health.provider == .codex
                ? "Start a new task to verify. Approve hooks or restart Codex if needed."
                : "Start a new task to verify. Restart the agent if needed."
            tone = .neutral
            action = nil
        case .connected:
            label = "Connected"
            detail = "Local task activity verified."
            tone = .positive
            action = nil
        }
    }

    public var accessibilityActionLabel: String? {
        action.map { "\($0.title) \(providerName)" }
    }

    public static func name(for provider: PetProvider) -> String {
        switch provider {
        case .codex: "Codex"
        case .claude: "Claude Code"
        case .cursor: "Cursor"
        }
    }

    /// Providers a user has not connected are optional, not failed setup steps.
    /// Connected means delivery has been verified; Ready has not received its
    /// first event since the current hook configuration was installed.
    public static func summary(for health: [ProviderIntegrationHealth]) -> String {
        let configured = health.filter { $0.state != .notInstalled }
        guard !configured.isEmpty else { return "Connect your agents" }
        if configured.contains(where: { $0.state == .needsUpdate || $0.state == .deliveryError }) {
            return "Connection needs attention"
        }
        let connectedCount = configured.filter { $0.state == .connected }.count
        let readyCount = configured.filter { $0.state == .noSignal }.count
        if connectedCount == 0 { return "Ready to verify" }
        if readyCount > 0 { return "\(connectedCount) connected · \(readyCount) ready" }
        return "\(connectedCount) connected"
    }
}

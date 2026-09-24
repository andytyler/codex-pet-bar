import Foundation

public enum ProviderIntegrationHealthState: String, CaseIterable, Sendable {
    case notInstalled
    case needsUpdate
    case deliveryError
    case noSignal
    case connected
}

public struct ProviderIntegrationHealth: Equatable, Sendable {
    public let provider: PetProvider
    public let state: ProviderIntegrationHealthState
    public let missingRequiredEvents: [String]
    public let hookRuntimeAvailable: Bool
    public let newestSuccessfulEventTimestamp: TimeInterval?
    public let newestDeliveryErrorTimestamp: TimeInterval?

    public init(
        provider: PetProvider,
        state: ProviderIntegrationHealthState,
        missingRequiredEvents: [String] = [],
        hookRuntimeAvailable: Bool = true,
        newestSuccessfulEventTimestamp: TimeInterval? = nil,
        newestDeliveryErrorTimestamp: TimeInterval? = nil
    ) {
        self.provider = provider
        self.state = state
        self.missingRequiredEvents = missingRequiredEvents
        self.hookRuntimeAvailable = hookRuntimeAvailable
        self.newestSuccessfulEventTimestamp = newestSuccessfulEventTimestamp
        self.newestDeliveryErrorTimestamp = newestDeliveryErrorTimestamp
    }
}

/// File contents are passed in by the app so evaluation stays deterministic,
/// testable, and free of filesystem or process-environment side effects.
public struct ProviderIntegrationHealthInput: Sendable {
    public let provider: PetProvider
    public let configData: Data?
    public let installedHookData: Data?
    public let currentHookData: Data?
    public let installedHookPath: String
    public let configModificationTimestamp: TimeInterval?
    public let installedHookModificationTimestamp: TimeInterval?
    public let hookRuntimeAvailable: Bool
    public let events: [CodexPetEvent]
    public let deliveryErrorMarkerData: [Data]

    public init(
        provider: PetProvider,
        configData: Data?,
        installedHookData: Data?,
        currentHookData: Data?,
        installedHookPath: String,
        configModificationTimestamp: TimeInterval? = nil,
        installedHookModificationTimestamp: TimeInterval? = nil,
        hookRuntimeAvailable: Bool = true,
        events: [CodexPetEvent],
        deliveryErrorMarkerData: [Data] = []
    ) {
        self.provider = provider
        self.configData = configData
        self.installedHookData = installedHookData
        self.currentHookData = currentHookData
        self.installedHookPath = installedHookPath
        self.configModificationTimestamp = configModificationTimestamp
        self.installedHookModificationTimestamp = installedHookModificationTimestamp
        self.hookRuntimeAvailable = hookRuntimeAvailable
        self.events = events
        self.deliveryErrorMarkerData = deliveryErrorMarkerData
    }
}

public enum ProviderIntegrationHealthEvaluator {
    public static func evaluate(_ input: ProviderIntegrationHealthInput) -> ProviderIntegrationHealth {
        let requiredEvents = requiredEventNames(for: input.provider)
        let configInspection = inspectConfig(
            input.configData,
            provider: input.provider,
            installedHookPath: input.installedHookPath
        )
        let missingEvents = requiredEvents.filter { !configInspection.currentEvents.contains($0) }
        let newestSuccessfulEventTimestamp = input.events.lazy
            .filter { $0.provider == input.provider }
            .map(\.timestamp)
            .max()
        let newestDeliveryErrorTimestamp = input.deliveryErrorMarkerData.compactMap {
            deliveryErrorTimestamp(in: $0, provider: input.provider)
        }
        .max()
        let verificationTimestamp = [
            input.configModificationTimestamp,
            input.installedHookModificationTimestamp,
        ]
        .compactMap { finiteTimestamp($0) }
        .max()
        let verifiedSuccessfulEventTimestamp = newestSuccessfulEventTimestamp.flatMap { timestamp in
            isCurrent(timestamp, verificationTimestamp: verificationTimestamp) ? timestamp : nil
        }
        let currentDeliveryErrorTimestamp = newestDeliveryErrorTimestamp.flatMap { timestamp in
            isCurrent(timestamp, verificationTimestamp: verificationTimestamp) ? timestamp : nil
        }

        guard configInspection.hasProviderPetHook else {
            return ProviderIntegrationHealth(
                provider: input.provider,
                state: .notInstalled,
                missingRequiredEvents: requiredEvents,
                hookRuntimeAvailable: input.hookRuntimeAvailable,
                newestSuccessfulEventTimestamp: newestSuccessfulEventTimestamp,
                newestDeliveryErrorTimestamp: newestDeliveryErrorTimestamp
            )
        }

        let hookBytesAreCurrent = input.installedHookData.map { installedData in
            input.currentHookData.map { installedData == $0 } ?? true
        } ?? false
        guard missingEvents.isEmpty, hookBytesAreCurrent else {
            return ProviderIntegrationHealth(
                provider: input.provider,
                state: .needsUpdate,
                missingRequiredEvents: missingEvents,
                hookRuntimeAvailable: input.hookRuntimeAvailable,
                newestSuccessfulEventTimestamp: newestSuccessfulEventTimestamp,
                newestDeliveryErrorTimestamp: newestDeliveryErrorTimestamp
            )
        }

        guard input.hookRuntimeAvailable else {
            return ProviderIntegrationHealth(
                provider: input.provider,
                state: .deliveryError,
                hookRuntimeAvailable: false,
                newestSuccessfulEventTimestamp: newestSuccessfulEventTimestamp,
                newestDeliveryErrorTimestamp: newestDeliveryErrorTimestamp
            )
        }

        if
            let currentDeliveryErrorTimestamp,
            verifiedSuccessfulEventTimestamp.map({ currentDeliveryErrorTimestamp > $0 }) ?? true
        {
            return ProviderIntegrationHealth(
                provider: input.provider,
                state: .deliveryError,
                hookRuntimeAvailable: input.hookRuntimeAvailable,
                newestSuccessfulEventTimestamp: newestSuccessfulEventTimestamp,
                newestDeliveryErrorTimestamp: newestDeliveryErrorTimestamp
            )
        }

        return ProviderIntegrationHealth(
            provider: input.provider,
            state: verifiedSuccessfulEventTimestamp == nil ? .noSignal : .connected,
            hookRuntimeAvailable: input.hookRuntimeAvailable,
            newestSuccessfulEventTimestamp: newestSuccessfulEventTimestamp,
            newestDeliveryErrorTimestamp: newestDeliveryErrorTimestamp
        )
    }

    public static func requiredEventNames(for provider: PetProvider) -> [String] {
        switch provider {
        case .codex:
            [
                "SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest",
                "PostToolUse", "SubagentStart", "SubagentStop", "PreCompact",
                "PostCompact", "Stop",
            ]
        case .claude:
            [
                "SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest",
                "PermissionDenied", "PostToolUse", "PostToolUseFailure", "Notification",
                "Elicitation", "ElicitationResult", "SubagentStart", "SubagentStop",
                "CwdChanged", "PreCompact", "PostCompact", "Stop", "StopFailure",
                "SessionEnd",
            ]
        case .cursor:
            [
                "sessionStart", "beforeSubmitPrompt", "preToolUse", "postToolUse",
                "postToolUseFailure", "afterAgentResponse", "subagentStart", "subagentStop",
                "preCompact", "stop", "sessionEnd",
            ]
        }
    }

    private static func inspectConfig(
        _ data: Data?,
        provider: PetProvider,
        installedHookPath: String
    ) -> ConfigInspection {
        guard
            let data,
            let object = try? JSONSerialization.jsonObject(with: data),
            let root = object as? [String: Any],
            let hooks = root["hooks"] as? [String: Any]
        else {
            // A malformed file which still mentions our hook is an installed
            // integration that needs repair, rather than a clean first install.
            return ConfigInspection(
                hasProviderPetHook: data.map {
                    configTextContainsProviderPetHook($0, provider: provider)
                } ?? false,
                currentEvents: []
            )
        }

        var hasProviderPetHook = false
        var currentEvents: Set<String> = []
        for (eventName, value) in hooks {
            let commands = provider == .cursor
                ? nativeCursorCommands(from: value)
                : groupedCommands(from: value)
            for command in commands where commandTargetsProvider(command, provider: provider) {
                hasProviderPetHook = true
                if commandTargetsCurrentHook(command, installedHookPath: installedHookPath) {
                    currentEvents.insert(eventName)
                }
            }
        }
        return ConfigInspection(
            hasProviderPetHook: hasProviderPetHook,
            currentEvents: currentEvents
        )
    }

    private static func groupedCommands(from value: Any) -> [String] {
        guard let entries = value as? [Any] else {
            return []
        }
        return entries.flatMap { entry -> [String] in
            guard
                let entry = entry as? [String: Any],
                let hooks = entry["hooks"] as? [Any]
            else {
                return []
            }
            return hooks.compactMap { hook in
                (hook as? [String: Any])?["command"] as? String
            }
        }
    }

    private static func nativeCursorCommands(from value: Any) -> [String] {
        guard let entries = value as? [Any] else {
            return []
        }
        return entries.compactMap { entry in
            (entry as? [String: Any])?["command"] as? String
        }
    }

    private static func commandTargetsProvider(_ command: String, provider: PetProvider) -> Bool {
        guard command.contains("codex_pet_event.py") else {
            return false
        }
        let providerAssignments = PetProvider.allCases.filter {
            command.contains("CODEX_PET_PROVIDER=\($0.rawValue)")
        }
        if providerAssignments.isEmpty {
            // Only Codex had an untagged legacy installation. Treat it as an
            // installed-but-old Codex hook, never as Claude or Cursor.
            return provider == .codex
        }
        return providerAssignments == [provider]
    }

    private static func commandTargetsCurrentHook(_ command: String, installedHookPath: String) -> Bool {
        !installedHookPath.isEmpty && command.contains(installedHookPath)
    }

    private static func configTextContainsProviderPetHook(_ data: Data, provider: PetProvider) -> Bool {
        guard let text = String(data: data, encoding: .utf8), text.contains("codex_pet_event.py") else {
            return false
        }
        if text.contains("CODEX_PET_PROVIDER=") {
            return text.contains("CODEX_PET_PROVIDER=\(provider.rawValue)")
        }
        return provider == .codex
    }

    private static func deliveryErrorTimestamp(in data: Data, provider: PetProvider) -> TimeInterval? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let marker = object as? [String: Any],
            marker["provider"] as? String == provider.rawValue,
            let timestamp = finiteTimestamp(marker["timestamp"])
        else {
            return nil
        }
        return timestamp
    }

    private static func finiteTimestamp(_ value: Any?) -> TimeInterval? {
        guard !(value is Bool) else {
            return nil
        }
        let timestamp: TimeInterval?
        if let value = value as? TimeInterval {
            timestamp = value
        } else if let value = value as? Int {
            timestamp = TimeInterval(value)
        } else if let value = value as? NSNumber {
            timestamp = value.doubleValue
        } else {
            timestamp = nil
        }
        guard let timestamp, timestamp.isFinite, timestamp >= 0 else {
            return nil
        }
        return timestamp
    }

    private static func isCurrent(
        _ timestamp: TimeInterval,
        verificationTimestamp: TimeInterval?
    ) -> Bool {
        guard let verificationTimestamp else {
            return true
        }
        return timestamp >= verificationTimestamp
    }

    private struct ConfigInspection {
        let hasProviderPetHook: Bool
        let currentEvents: Set<String>
    }
}

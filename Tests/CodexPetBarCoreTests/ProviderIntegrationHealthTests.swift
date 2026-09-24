import Foundation
import Testing
@testable import CodexPetBarCore

@Suite("Provider integration health")
struct ProviderIntegrationHealthTests {
    private let installedPath = "/Users/tester/.codex/hooks/codex_pet_event.py"
    private let currentHook = Data("current hook".utf8)

    @Test("required lifecycle surfaces remain explicit for every provider")
    func requiredLifecycleSurfaces() {
        #expect(
            Set(ProviderIntegrationHealthEvaluator.requiredEventNames(for: .codex)) == [
                "SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest",
                "PostToolUse", "SubagentStart", "SubagentStop", "PreCompact",
                "PostCompact", "Stop",
            ]
        )
        #expect(
            Set(ProviderIntegrationHealthEvaluator.requiredEventNames(for: .claude)) == [
                "SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest",
                "PermissionDenied", "PostToolUse", "PostToolUseFailure", "Notification",
                "Elicitation", "ElicitationResult", "SubagentStart", "SubagentStop",
                "CwdChanged", "PreCompact", "PostCompact", "Stop", "StopFailure",
                "SessionEnd",
            ]
        )
        #expect(
            Set(ProviderIntegrationHealthEvaluator.requiredEventNames(for: .cursor)) == [
                "sessionStart", "beforeSubmitPrompt", "preToolUse", "postToolUse",
                "postToolUseFailure", "afterAgentResponse", "subagentStart", "subagentStop",
                "preCompact", "stop", "sessionEnd",
            ]
        )
    }

    @Test("missing and foreign hook configs are not installed")
    func missingConfigIsNotInstalled() throws {
        let missing = evaluate(provider: .codex, configData: nil)
        let foreign = evaluate(
            provider: .claude,
            configData: try jsonData([
                "hooks": [
                    "SessionStart": [[
                        "hooks": [["type": "command", "command": "/usr/bin/true"]],
                    ]],
                ],
            ])
        )

        #expect(missing.state == .notInstalled)
        #expect(missing.missingRequiredEvents.count == 10)
        #expect(foreign.state == .notInstalled)
    }

    @Test("partial, malformed, and legacy provider hooks need an update")
    func incompleteConfigNeedsUpdate() throws {
        let command = providerCommand(.claude)
        let partial = try jsonData([
            "hooks": [
                "SessionStart": [[
                    "hooks": [["type": "command", "command": command]],
                ]],
            ],
        ])
        let malformed = Data("{ broken CODEX_PET_PROVIDER=claude codex_pet_event.py".utf8)
        let legacyCodex = try groupedConfig(
            provider: .codex,
            command: "/usr/bin/python3 /old/hooks/codex_pet_event.py"
        )

        #expect(evaluate(provider: .claude, configData: partial).state == .needsUpdate)
        #expect(evaluate(provider: .claude, configData: malformed).state == .needsUpdate)
        #expect(evaluate(provider: .codex, configData: legacyCodex).state == .needsUpdate)
    }

    @Test("all required grouped and native Cursor hook entries are recognized")
    func recognizesCurrentHookSurfaces() throws {
        for provider in PetProvider.allCases {
            let result = evaluate(
                provider: provider,
                configData: try config(provider: provider),
                currentHookData: nil
            )
            #expect(result.state == .noSignal)
            #expect(result.missingRequiredEvents.isEmpty)
        }
    }

    @Test("a missing or stale installed hook script needs an update")
    func staleScriptNeedsUpdate() throws {
        let configData = try config(provider: .cursor)
        let missing = evaluate(
            provider: .cursor,
            configData: configData,
            installedHookData: nil
        )
        let stale = evaluate(
            provider: .cursor,
            configData: configData,
            installedHookData: Data("old hook".utf8)
        )

        #expect(missing.state == .needsUpdate)
        #expect(stale.state == .needsUpdate)
    }

    @Test("a missing hook runtime reports a delivery error after configuration is current")
    func missingRuntimeIsDeliveryError() throws {
        let result = ProviderIntegrationHealthEvaluator.evaluate(
            ProviderIntegrationHealthInput(
                provider: .codex,
                configData: try config(provider: .codex),
                installedHookData: currentHook,
                currentHookData: currentHook,
                installedHookPath: installedPath,
                hookRuntimeAvailable: false,
                events: []
            )
        )

        #expect(result.state == .deliveryError)
        #expect(!result.hookRuntimeAvailable)
    }

    @Test("newer delivery failure markers outrank prior successful events")
    func deliveryFailureOutranksPriorEvent() throws {
        let event = CodexPetEvent(
            kind: "tool_started",
            timestamp: 100,
            provider: .claude,
            sessionID: "session"
        )
        let adjacentMarker = try marker(provider: .claude, timestamp: 110)
        let olderFallbackMarker = try marker(provider: .claude, timestamp: 90)
        let result = evaluate(
            provider: .claude,
            configData: try config(provider: .claude),
            events: [event],
            markerData: [olderFallbackMarker, adjacentMarker]
        )

        #expect(result.state == .deliveryError)
        #expect(result.newestSuccessfulEventTimestamp == 100)
        #expect(result.newestDeliveryErrorTimestamp == 110)
    }

    @Test("a successful event newer than both marker locations recovers health")
    func newerEventRecoversHealth() throws {
        let result = evaluate(
            provider: .cursor,
            configData: try config(provider: .cursor),
            events: [
                CodexPetEvent(
                    kind: "stopped",
                    timestamp: 120,
                    provider: .cursor,
                    sessionID: "session"
                ),
            ],
            markerData: [
                try marker(provider: .cursor, timestamp: 100),
                try marker(provider: .cursor, timestamp: 110),
            ]
        )

        #expect(result.state == .connected)
        #expect(result.newestDeliveryErrorTimestamp == 110)
    }

    @Test("an event from before the current install does not claim a connection")
    func staleEventRequiresPostInstallSignal() throws {
        let stale = evaluate(
            provider: .cursor,
            configData: try config(provider: .cursor),
            configModificationTimestamp: 110,
            installedHookModificationTimestamp: 120,
            events: [
                CodexPetEvent(
                    kind: "stopped",
                    timestamp: 115,
                    provider: .cursor,
                    sessionID: "session"
                ),
            ]
        )
        let verified = evaluate(
            provider: .cursor,
            configData: try config(provider: .cursor),
            configModificationTimestamp: 110,
            installedHookModificationTimestamp: 120,
            events: [
                CodexPetEvent(
                    kind: "session_started",
                    timestamp: 120,
                    provider: .cursor,
                    sessionID: "session"
                ),
            ]
        )

        #expect(stale.state == .noSignal)
        #expect(stale.newestSuccessfulEventTimestamp == 115)
        #expect(verified.state == .connected)
    }

    @Test("repair ignores delivery errors from the prior installation")
    func staleDeliveryErrorDoesNotSurviveRepair() throws {
        let result = evaluate(
            provider: .claude,
            configData: try config(provider: .claude),
            configModificationTimestamp: 120,
            installedHookModificationTimestamp: 110,
            events: [
                CodexPetEvent(
                    kind: "tool_started",
                    timestamp: 100,
                    provider: .claude,
                    sessionID: "session"
                ),
            ],
            markerData: [try marker(provider: .claude, timestamp: 115)]
        )

        #expect(result.state == .noSignal)
        #expect(result.newestDeliveryErrorTimestamp == 115)
    }

    @Test("a fallback-only failure is visible and another provider's marker is ignored")
    func fallbackMarkerAndProviderIsolation() throws {
        let fallbackFailure = evaluate(
            provider: .codex,
            configData: try config(provider: .codex),
            markerData: [try marker(provider: .codex, timestamp: 100)]
        )
        let unrelatedMarker = evaluate(
            provider: .codex,
            configData: try config(provider: .codex),
            markerData: [try marker(provider: .claude, timestamp: 100)]
        )

        #expect(fallbackFailure.state == .deliveryError)
        #expect(unrelatedMarker.state == .noSignal)
    }

    @Test("non-finite, negative, boolean, and malformed marker timestamps are ignored")
    func invalidMarkersAreIgnored() throws {
        let markerData = [
            try jsonData(["provider": "codex", "timestamp": -1]),
            try jsonData(["provider": "codex", "timestamp": true]),
            Data(#"{"provider":"codex","timestamp":1e999}"#.utf8),
            Data("not json".utf8),
        ]
        let result = evaluate(
            provider: .codex,
            configData: try config(provider: .codex),
            markerData: markerData
        )

        #expect(result.state == .noSignal)
        #expect(result.newestDeliveryErrorTimestamp == nil)
    }

    private func evaluate(
        provider: PetProvider,
        configData: Data?,
        installedHookData: Data? = Data("current hook".utf8),
        currentHookData: Data? = Data("current hook".utf8),
        configModificationTimestamp: TimeInterval? = nil,
        installedHookModificationTimestamp: TimeInterval? = nil,
        events: [CodexPetEvent] = [],
        markerData: [Data] = []
    ) -> ProviderIntegrationHealth {
        ProviderIntegrationHealthEvaluator.evaluate(
            ProviderIntegrationHealthInput(
                provider: provider,
                configData: configData,
                installedHookData: installedHookData,
                currentHookData: currentHookData,
                installedHookPath: installedPath,
                configModificationTimestamp: configModificationTimestamp,
                installedHookModificationTimestamp: installedHookModificationTimestamp,
                events: events,
                deliveryErrorMarkerData: markerData
            )
        )
    }

    private func config(provider: PetProvider) throws -> Data {
        if provider == .cursor {
            let hooks = Dictionary(
                uniqueKeysWithValues: ProviderIntegrationHealthEvaluator
                    .requiredEventNames(for: provider)
                    .map { ($0, [["command": providerCommand(provider), "timeout": 5] as [String: Any]]) }
            )
            return try jsonData(["version": 1, "hooks": hooks])
        }
        return try groupedConfig(provider: provider, command: providerCommand(provider))
    }

    private func groupedConfig(provider: PetProvider, command: String) throws -> Data {
        let hooks = Dictionary(
            uniqueKeysWithValues: ProviderIntegrationHealthEvaluator
                .requiredEventNames(for: provider)
                .map {
                    (
                        $0,
                        [[
                            "matcher": "*",
                            "hooks": [[
                                "type": "command",
                                "command": command,
                                "timeout": 5,
                            ] as [String: Any]],
                        ] as [String: Any]]
                    )
                }
        )
        return try jsonData(["hooks": hooks])
    }

    private func providerCommand(_ provider: PetProvider) -> String {
        "CODEX_PET_PROVIDER=\(provider.rawValue) /usr/bin/python3 \(installedPath)"
    }

    private func marker(provider: PetProvider, timestamp: TimeInterval) throws -> Data {
        try jsonData([
            "version": 1,
            "provider": provider.rawValue,
            "timestamp": timestamp,
            "error_type": "OSError",
        ])
    }

    private func jsonData(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

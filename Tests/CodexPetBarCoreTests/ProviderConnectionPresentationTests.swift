import Testing
@testable import CodexPetBarCore

@Suite("Provider connection presentation")
struct ProviderConnectionPresentationTests {
    @Test("absent providers are optional and offer provider-specific connect actions")
    func absentProvidersAreOptional() {
        for provider in PetProvider.allCases {
            let value = presentation(provider, .notInstalled)
            #expect(value.label == "Optional")
            #expect(value.tone == .neutral)
            #expect(value.action == .connect)
            #expect(value.accessibilityActionLabel == "Connect \(value.providerName)")
        }
    }

    @Test("configured hooks awaiting their first event are ready, not disconnected")
    func awaitingActivityIsReady() {
        for provider in PetProvider.allCases {
            let value = presentation(provider, .noSignal)
            #expect(value.label == "Ready")
            #expect(value.tone == .neutral)
            #expect(value.action == nil)
            #expect(value.detail.contains("Start a new task"))
        }
        #expect(presentation(.codex, .noSignal).detail.contains("Approve hooks"))
    }

    @Test("verified delivery is positive without unnecessary reinstall")
    func connectedDoesNotOfferReinstall() {
        let value = presentation(.codex, .connected)
        #expect(value.label == "Connected")
        #expect(value.tone == .positive)
        #expect(value.action == nil)
    }

    @Test("repair actions distinguish outdated hooks from delivery failures")
    func actionableFailures() {
        let stale = presentation(.claude, .needsUpdate)
        let failed = presentation(.cursor, .deliveryError)
        #expect(stale.action == .repair)
        #expect(stale.accessibilityActionLabel == "Repair Claude Code")
        #expect(failed.action == .reconnect)
        #expect(failed.accessibilityActionLabel == "Reconnect Cursor")
        #expect(stale.tone == .attention)
        #expect(failed.tone == .attention)
    }

    @Test("missing Python explains the prerequisite instead of offering a repair that cannot fix it")
    func missingRuntimeHasUsefulGuidance() {
        let value = ProviderConnectionPresentation(health: ProviderIntegrationHealth(
            provider: .codex, state: .deliveryError, hookRuntimeAvailable: false
        ))
        #expect(value.action == nil)
        #expect(value.detail.contains("Python is unavailable"))
        #expect(value.detail.contains("Command Line Tools"))
        #expect(value.tone == .attention)
    }

    @Test("an unconnected optional provider never makes successful setup look incomplete")
    func optionalProvidersDoNotCountAgainstSetup() {
        #expect(ProviderConnectionPresentation.summary(for: [
            health(.codex, .connected), health(.claude, .notInstalled), health(.cursor, .notInstalled)
        ]) == "1 connected")
        #expect(ProviderConnectionPresentation.summary(for: [
            health(.codex, .noSignal), health(.claude, .notInstalled)
        ]) == "Ready to verify")
    }

    @Test("summary separates verified providers from providers waiting for first delivery")
    func mixedVerificationSummary() {
        #expect(ProviderConnectionPresentation.summary(for: [
            health(.codex, .connected), health(.claude, .noSignal), health(.cursor, .notInstalled)
        ]) == "1 connected · 1 ready")
    }

    @Test("real connection failures remain visible even when another provider works")
    func errorsTakePrecedence() {
        for state in [ProviderIntegrationHealthState.needsUpdate, .deliveryError] {
            #expect(ProviderConnectionPresentation.summary(for: [
                health(.codex, .connected), health(.claude, state), health(.cursor, .notInstalled)
            ]) == "Connection needs attention")
        }
    }

    @Test("empty and entirely unconfigured lists invite connecting agents")
    func noConfigurationSummary() {
        #expect(ProviderConnectionPresentation.summary(for: []) == "Connect your agents")
        #expect(ProviderConnectionPresentation.summary(for: PetProvider.allCases.map {
            health($0, .notInstalled)
        }) == "Connect your agents")
    }

    private func health(_ provider: PetProvider, _ state: ProviderIntegrationHealthState) -> ProviderIntegrationHealth {
        ProviderIntegrationHealth(provider: provider, state: state)
    }

    private func presentation(_ provider: PetProvider, _ state: ProviderIntegrationHealthState) -> ProviderConnectionPresentation {
        ProviderConnectionPresentation(health: health(provider, state))
    }
}

import Foundation
import Testing
@testable import CodexPetBarCore

@Suite("Login item consent")
@MainActor
struct LoginItemConsentTests {
    @Test("An installed app with an unavailable service asks once without registering until accepted", arguments: [false, true])
    func unavailableServiceStillRequiresConsent(accepted: Bool) throws {
        let suite = "LoginItemConsentTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = FakeLoginItemService()
        service.status = .unavailable
        let consent = LoginItemConsent(defaults: defaults, service: service, registrationAllowed: true)
        #expect(consent.shouldPrompt)
        #expect(!consent.hasAsked)
        #expect(service.registerCount == 0)

        try consent.respondToPrompt(allow: accepted)
        #expect(service.registerCount == (accepted ? 1 : 0))
        #expect(consent.status == (accepted ? .enabled : .unavailable))
        let nextLaunch = LoginItemConsent(defaults: defaults, service: service, registrationAllowed: true)
        #expect(nextLaunch.hasAsked)
        #expect(!nextLaunch.shouldPrompt)
    }

    @Test("Existing registration or pending system approval does not prompt again", arguments: [LoginItemStatus.enabled, .requiresApproval])
    func existingSystemChoiceIsRespected(status: LoginItemStatus) throws {
        let suite = "LoginItemConsentTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = FakeLoginItemService()
        service.status = status
        let consent = LoginItemConsent(defaults: defaults, service: service, registrationAllowed: true)
        #expect(!consent.shouldPrompt)
        #expect(!consent.hasAsked)
        #expect(service.registerCount == 0)
    }

    @Test("Not Now persists across launches and never registers")
    func declineIsRemembered() throws {
        let suite = "LoginItemConsentTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = FakeLoginItemService()
        let first = LoginItemConsent(defaults: defaults, service: service, registrationAllowed: true)
        #expect(first.shouldPrompt)
        try first.respondToPrompt(allow: false)
        let second = LoginItemConsent(defaults: defaults, service: service, registrationAllowed: true)
        #expect(!second.shouldPrompt)
        #expect(service.registerCount == 0)
        try second.setEnabled(true)
        #expect(service.registerCount == 1)
        #expect(second.status == .enabled)
        try second.setEnabled(false)
        #expect(service.unregisterCount == 1)
        #expect(!second.shouldPrompt)
    }

    @Test("Acceptance registers once and pending approval is not reported enabled")
    func approvalStatus() throws {
        let suite = "LoginItemConsentTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = FakeLoginItemService()
        service.registrationResult = .requiresApproval
        let consent = LoginItemConsent(defaults: defaults, service: service, registrationAllowed: true)
        try consent.respondToPrompt(allow: true)
        #expect(consent.status == .requiresApproval)
        #expect(!consent.shouldPrompt)
        try consent.setEnabled(true)
        #expect(service.registerCount == 1)
        try consent.setEnabled(false)
        #expect(consent.status == .notRegistered)
        #expect(service.unregisterCount == 1)
    }

    @Test("A registration error preserves consent history and actual disabled state")
    func registrationFailure() throws {
        let suite = "LoginItemConsentTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = FakeLoginItemService()
        service.shouldFail = true
        let consent = LoginItemConsent(defaults: defaults, service: service, registrationAllowed: true)
        #expect(throws: FakeLoginItemService.Failure.self) { try consent.respondToPrompt(allow: true) }
        #expect(consent.status == .notRegistered)
        #expect(!consent.shouldPrompt)
        service.shouldFail = false
        try consent.setEnabled(true)
        #expect(consent.status == .enabled)
    }

    @Test("Development and preview launches cannot ask, register, unregister, or persist a choice")
    func developmentLaunch() throws {
        let suite = "LoginItemConsentTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = FakeLoginItemService()
        let consent = LoginItemConsent(defaults: defaults, service: service, registrationAllowed: false)
        #expect(!consent.shouldPrompt)
        try consent.respondToPrompt(allow: true)
        try consent.setEnabled(true)
        service.status = .enabled
        try consent.setEnabled(false)
        #expect(service.registerCount == 0)
        #expect(service.unregisterCount == 0)
        #expect(!consent.hasAsked)
    }

    @Test("Only the installed app in a normal launch is eligible")
    func launchEligibility() {
        let home = URL(fileURLWithPath: "/Users/login-policy-test", isDirectory: true)
        func allowed(_ path: String, _ args: [String] = [], id: String = "dev.ajt.CodexPetBar") -> Bool {
            LoginItemConsent.registrationAllowed(bundleURL: URL(fileURLWithPath: path, isDirectory: true), bundleIdentifier: id, arguments: args, homeDirectory: home)
        }
        #expect(allowed("/Applications/CodexPetBar.app"))
        #expect(allowed("/Users/login-policy-test/Applications/CodexPetBar.app"))
        #expect(!allowed("/tmp/dist/CodexPetBar.app"))
        #expect(!allowed("/Applications/../tmp/CodexPetBar.app"))
        #expect(!allowed("/Applications/CodexPetBar.app", id: "example.other"))
        #expect(!allowed("/Applications/CodexPetBar.app", ["--preview-task-panel"]))
        #expect(!allowed("/Applications/CodexPetBar.app", ["--render-menu-bar-states=/tmp/image.png"]))
    }
}

@MainActor
private final class FakeLoginItemService: LoginItemService {
    enum Failure: Error { case registrationFailed }
    var status: LoginItemStatus = .notRegistered
    var registrationResult: LoginItemStatus = .enabled
    var shouldFail = false
    var registerCount = 0
    var unregisterCount = 0
    func register() throws {
        registerCount += 1
        if shouldFail { throw Failure.registrationFailed }
        status = registrationResult
    }
    func unregister() throws {
        unregisterCount += 1
        status = .notRegistered
    }
}

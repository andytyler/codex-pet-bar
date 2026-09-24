import AppKit
import CodexPetBarCore
import ServiceManagement

@MainActor
private final class SystemLoginItemService: LoginItemService {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

@MainActor
final class LoginItemController: NSObject {
    /// Read-only support output. This never creates the status item, prompts, or
    /// calls any ServiceManagement registration API.
    static func diagnosticData() throws -> Data {
        let consent = LoginItemConsent(
            defaults: .standard,
            service: SystemLoginItemService(),
            registrationAllowed: LoginItemConsent.registrationAllowed(
                bundleURL: Bundle.main.bundleURL,
                bundleIdentifier: Bundle.main.bundleIdentifier,
                arguments: ProcessInfo.processInfo.arguments
            )
        )
        let systemStatus = SMAppService.mainApp.status
        let statusName: String
        switch systemStatus {
        case .notRegistered: statusName = "notRegistered"
        case .enabled: statusName = "enabled"
        case .requiresApproval: statusName = "requiresApproval"
        case .notFound: statusName = "notFound"
        @unknown default: statusName = "unknown"
        }
        let diagnostic: [String: Any] = [
            "bundlePath": Bundle.main.bundleURL.path,
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
            "executablePath": Bundle.main.executableURL?.path ?? "",
            "systemStatus": statusName,
            "systemStatusRawValue": systemStatus.rawValue,
            "registrationAllowed": consent.registrationAllowed,
            "hasAsked": consent.hasAsked,
            "shouldPrompt": consent.shouldPrompt,
        ]
        return try JSONSerialization.data(withJSONObject: diagnostic, options: [.prettyPrinted, .sortedKeys])
    }

    private let consent = LoginItemConsent(
        defaults: .standard,
        service: SystemLoginItemService(),
        registrationAllowed: LoginItemConsent.registrationAllowed(
            bundleURL: Bundle.main.bundleURL,
            bundleIdentifier: Bundle.main.bundleIdentifier,
            arguments: ProcessInfo.processInfo.arguments
        )
    )

    func promptOnFirstLaunch() {
        guard consent.shouldPrompt else { return }
        let alert = NSAlert()
        alert.messageText = "Open CodexPetBar when you log in?"
        alert.informativeText = "Keep your pet in the menu bar whenever you use your Mac. You can change this later in the pet menu."
        alert.addButton(withTitle: "Open at Login")
        alert.addButton(withTitle: "Not Now")
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        NSApp.activate(ignoringOtherApps: true)
        let accepted = alert.runModal() == .alertFirstButtonReturn
        do {
            try consent.respondToPrompt(allow: accepted)
            if accepted { showRegistrationOutcome() }
        } catch {
            showError(error)
        }
    }

    func addMenuItems(to menu: NSMenu) {
        let item = NSMenuItem(title: "Open at Login", action: #selector(toggleOpenAtLogin), keyEquivalent: "")
        item.target = self
        item.isEnabled = consent.registrationAllowed
        switch consent.status {
        case .enabled: item.state = .on
        case .requiresApproval:
            item.state = .mixed
            item.title = "Open at Login · Needs Approval"
        case .notRegistered, .unavailable: item.state = .off
        }
        if !consent.registrationAllowed {
            item.toolTip = "Install CodexPetBar in Applications to enable Open at Login. Preview builds cannot change login items."
        }
        menu.addItem(item)
        if consent.registrationAllowed && consent.status == .requiresApproval {
            let settings = NSMenuItem(title: "Approve in Login Items Settings…", action: #selector(openLoginItemsSettings), keyEquivalent: "")
            settings.target = self
            menu.addItem(settings)
        }
    }

    @objc private func toggleOpenAtLogin() {
        guard consent.registrationAllowed else { return }
        let enable = consent.status != .enabled && consent.status != .requiresApproval
        do {
            try consent.setEnabled(enable)
            if enable { showRegistrationOutcome() }
        } catch {
            showError(error)
        }
    }

    private func showRegistrationOutcome() {
        if consent.status == .requiresApproval {
            showApprovalNeeded()
        } else if consent.status != .enabled {
            showErrorMessage("macOS has not enabled CodexPetBar at login. Try again from the pet menu after confirming the app is installed in Applications.")
        }
    }

    private func showError(_ error: Error) {
        if consent.status == .requiresApproval { showApprovalNeeded() }
        else { showErrorMessage(error.localizedDescription) }
    }

    private func showErrorMessage(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could not change Open at Login"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showApprovalNeeded() {
        let alert = NSAlert()
        alert.messageText = "Allow CodexPetBar in Login Items"
        alert.informativeText = "macOS needs your approval before CodexPetBar can open at login. Enable it in System Settings → General → Login Items."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { openLoginItemsSettings() }
    }

    @objc private func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

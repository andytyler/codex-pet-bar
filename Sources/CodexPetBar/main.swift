import AppKit

// Run before creating NSApplication so support diagnostics cannot start the pet,
// present consent, or change login registration, including from a CLI invocation.
if let diagnosticArgument = ProcessInfo.processInfo.arguments.first(where: {
    $0 == "--diagnose-login" || $0.hasPrefix("--diagnose-login=")
}) {
    do {
        var data = try LoginItemController.diagnosticData()
        data.append(0x0a)
        if diagnosticArgument == "--diagnose-login" {
            FileHandle.standardOutput.write(data)
        } else {
            let path = String(diagnosticArgument.dropFirst("--diagnose-login=".count))
            guard path.hasPrefix("/") else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Could not diagnose login item: \(error)\n".utf8))
        exit(1)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusPetController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--render-task-pets=") }) {
            do {
                try PetTaskStripPreviewRenderer.render(
                    to: URL(fileURLWithPath: String(argument.dropFirst("--render-task-pets=".count))),
                    dark: ProcessInfo.processInfo.arguments.contains("--preview-dark")
                )
            } catch {
                FileHandle.standardError.write(Data("Could not render task pets: \(error)\n".utf8))
                exit(1)
            }
            NSApp.terminate(nil)
            return
        }
        if let renderArgument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--render-task-panel=") }) {
            let path = String(renderArgument.dropFirst("--render-task-panel=".count))
            do {
                try PetHoverPanelPreviewRenderer.render(
                    to: URL(fileURLWithPath: path),
                    empty: ProcessInfo.processInfo.arguments.contains("--preview-empty"),
                    connections: ProcessInfo.processInfo.arguments.contains("--preview-connections"),
                    dark: ProcessInfo.processInfo.arguments.contains("--preview-dark")
                )
            } catch {
                FileHandle.standardError.write(Data("Could not render task panel: \(error)\n".utf8))
            }
            NSApp.terminate(nil)
            return
        }
        if let renderArgument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--render-provider-flags=") }) {
            let path = String(renderArgument.dropFirst("--render-provider-flags=".count))
            do {
                try StatusPetController.renderProviderFlagPreview(to: URL(fileURLWithPath: path))
            } catch {
                FileHandle.standardError.write(Data("Could not render provider flags: \(error)\n".utf8))
            }
            NSApp.terminate(nil)
            return
        }
        if let renderArgument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--render-attention-flags=") }) {
            let path = String(renderArgument.dropFirst("--render-attention-flags=".count))
            do {
                try StatusPetController.renderAttentionFlagPreview(to: URL(fileURLWithPath: path))
            } catch {
                FileHandle.standardError.write(Data("Could not render attention flags: \(error)\n".utf8))
            }
            NSApp.terminate(nil)
            return
        }
        if let renderArgument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--render-menu-bar-states=") }) {
            let path = String(renderArgument.dropFirst("--render-menu-bar-states=".count))
            do {
                try StatusPetController.renderMenuBarStatesPreview(to: URL(fileURLWithPath: path))
            } catch {
                FileHandle.standardError.write(Data("Could not render menu bar states: \(error)\n".utf8))
                exit(1)
            }
            NSApp.terminate(nil)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--preview-task-panel") {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        let controller = StatusPetController()
        controller.start()
        self.controller = controller
        DispatchQueue.main.async { [weak controller] in
            controller?.offerOpenAtLoginIfNeeded()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.presentTaskPanel()
        return false
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

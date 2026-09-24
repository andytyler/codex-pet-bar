import Foundation
import Testing
@testable import CodexPetBarCore

@Suite("Codex environment")
struct CodexEnvironmentTests {
    @Test("uses the standard Codex home when no override exists")
    func usesDefaultHome() {
        let userHome = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

        let result = CodexEnvironment.homeDirectory(
            environment: [:],
            userHomeDirectory: userHome
        )

        #expect(result.path == "/Users/tester/.codex")
    }

    @Test("resolves absolute, tilde, and relative overrides consistently with the installer")
    func resolvesOverrides() {
        let userHome = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let workingDirectory = URL(fileURLWithPath: "/work/project", isDirectory: true)

        #expect(
            CodexEnvironment.homeDirectory(
                environment: ["CODEX_HOME": "/Volumes/codex-home"],
                userHomeDirectory: userHome,
                currentDirectory: workingDirectory
            ).path == "/Volumes/codex-home"
        )
        #expect(
            CodexEnvironment.homeDirectory(
                environment: ["CODEX_HOME": "~/alternate-codex"],
                userHomeDirectory: userHome,
                currentDirectory: workingDirectory
            ).path == "/Users/tester/alternate-codex"
        )
        #expect(
            CodexEnvironment.homeDirectory(
                environment: ["CODEX_HOME": "local-codex"],
                userHomeDirectory: userHome,
                currentDirectory: workingDirectory
            ).path == "/work/project/local-codex"
        )
    }

    @Test("ignores an empty override")
    func ignoresEmptyOverride() {
        let result = CodexEnvironment.homeDirectory(
            environment: ["CODEX_HOME": "   "],
            userHomeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        )

        #expect(result.path == "/Users/tester/.codex")
    }
}

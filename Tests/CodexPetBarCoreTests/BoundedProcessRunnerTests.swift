import Foundation
import Testing
@testable import CodexPetBarCore

@Suite("Bounded installer process")
struct BoundedProcessRunnerTests {
    @Test("Omitting the environment preserves the parent environment")
    func inheritsParentEnvironment() throws {
        let parent = ProcessInfo.processInfo.environment
        let key = try #require(["PATH", "USER"].first { parent[$0] != nil })
        let expected = try #require(parent[key])
        let result = BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: [
                "-c",
                "import os, sys; sys.exit(0 if os.environ.get(sys.argv[1]) == sys.argv[2] else 1)",
                key,
                expected,
            ],
            timeout: 10
        )

        #expect(result.failure == nil)
        #expect(result.exitCode == 0)
        #expect(result.output.isEmpty)
    }

    @Test("Explicit provider roots are preserved without merging the parent environment")
    func explicitEnvironmentReplacesParent() throws {
        let parent = ProcessInfo.processInfo.environment
        let parentKey = try #require(["PATH", "USER"].first { parent[$0] != nil })
        let environment = [
            "CODEX_HOME": "/private/tmp/codex-pet-test/codex root",
            "CLAUDE_CONFIG_DIR": "/private/tmp/codex-pet-test/claude root",
            "CURSOR_CONFIG_DIR": "/private/tmp/codex-pet-test/cursor root",
        ]
        let encoded = try JSONSerialization.data(withJSONObject: environment, options: .sortedKeys)
        let result = BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: [
                "-c",
                """
                import json, os, sys
                expected = json.loads(sys.argv[1])
                matches = all(os.environ.get(key) == value for key, value in expected.items())
                sys.exit(0 if matches and sys.argv[2] not in os.environ else 1)
                """,
                String(decoding: encoded, as: UTF8.self),
                parentKey,
            ],
            environment: environment,
            timeout: 10
        )

        #expect(result.failure == nil)
        #expect(result.exitCode == 0)
        #expect(result.output.isEmpty)
    }

    @Test("A missing executable returns its launch error without waiting for EOF")
    func failedLaunch() {
        let start = Date()
        let result = BoundedProcessRunner.run(executableURL: URL(fileURLWithPath: "/nonexistent/codex-pet-test-executable"), arguments: [], timeout: 2)
        #expect(result.failure != nil)
        #expect(result.exitCode != 0)
        #expect(Date().timeIntervalSince(start) < 2)
    }

    @Test("Large simultaneous stdout and stderr do not block child exit")
    func largeOutput() {
        let result = BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: ["-c", "import sys; sys.stdout.write('o' * 200000); sys.stderr.write('e' * 200000)"],
            timeout: 10
        )
        #expect(result.failure == nil)
        #expect(result.exitCode == 0)
        #expect(result.output.count == 200000)
        #expect(result.error.hasSuffix(String(repeating: "e", count: 200000)))
    }

    @Test("A stuck child is terminated within a bounded time")
    func timeout() {
        let start = Date()
        let result = BoundedProcessRunner.run(executableURL: URL(fileURLWithPath: "/usr/bin/python3"), arguments: ["-c", "import time; time.sleep(30)"], timeout: 0.2)
        #expect(result.failure?.contains("timed out") == true)
        #expect(result.exitCode != 0)
        #expect(Date().timeIntervalSince(start) < 4)
    }
}

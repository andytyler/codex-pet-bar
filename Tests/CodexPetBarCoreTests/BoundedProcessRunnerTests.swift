import Foundation
import Testing
@testable import CodexPetBarCore

@Suite("Bounded installer process")
struct BoundedProcessRunnerTests {
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

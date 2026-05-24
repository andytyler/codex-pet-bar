import Foundation
import Testing
@testable import CodexPetBarCore

@Suite("Codex thread menu")
struct CodexThreadMenuTests {
    @Test("session index parser returns recent threads newest first")
    func sessionIndexParserReturnsRecentThreadsNewestFirst() throws {
        let log = """
        {"id":"thread-old","thread_name":"Older thread","updated_at":"2026-05-18T09:28:52.144891Z"}
        {"id":"thread-new","thread_name":"Newer   thread","updated_at":"2026-05-18T21:17:00.882131Z"}
        """

        let threads = CodexSessionIndexLog.recentThreads(jsonLines: log, limit: 4)

        #expect(threads.map(\.id) == ["thread-new", "thread-old"])
        #expect(threads[0].title == "Newer thread")
    }

    @Test("thread menu rows include Codex thread deeplinks")
    func threadMenuRowsIncludeCodexThreadDeeplinks() {
        let threads = [
            CodexThreadSummary(id: "thread-a", title: "First", updatedAt: Date(timeIntervalSince1970: 2), folderTitle: "pet-bar"),
            CodexThreadSummary(id: "thread-b", title: "Second", updatedAt: Date(timeIntervalSince1970: 1), folderTitle: "luma-mcp")
        ]

        let rows = CodexThreadMenuRows.build(threads: threads)

        #expect(rows.map(\.id) == ["thread-a", "thread-b"])
        #expect(rows[0].deepLinkURL == URL(string: "codex://threads/thread-a"))
        #expect(rows[1].deepLinkURL == URL(string: "codex://threads/thread-b"))
    }

    @Test("thread menu sections group rows by folder title")
    func threadMenuSectionsGroupRowsByFolderTitle() {
        let rows = [
            CodexThreadMenuRow(id: "thread-a", title: "First", folderTitle: "pet-bar"),
            CodexThreadMenuRow(id: "thread-b", title: "Second", folderTitle: "luma-mcp"),
            CodexThreadMenuRow(id: "thread-c", title: "Third", folderTitle: "pet-bar")
        ]

        let sections = CodexThreadMenuSections.build(rows: rows)

        #expect(sections.map(\.folderTitle) == ["pet-bar", "luma-mcp"])
        #expect(sections[0].rows.map(\.id) == ["thread-a", "thread-c"])
        #expect(sections[1].rows.map(\.id) == ["thread-b"])
    }

    @Test("thread menu entries show running and recent groups with overflow")
    func threadMenuEntriesShowRunningAndRecentGroupsWithOverflow() {
        let rows = [
            CodexThreadMenuRow(id: "thread-a", title: "Fix checkout /v2/send payload", folderTitle: "enterprise-sdk"),
            CodexThreadMenuRow(id: "thread-b", title: "Create menu bar pet", folderTitle: "codex-pet-bar"),
            CodexThreadMenuRow(id: "thread-c", title: "Show permission state", folderTitle: "codex-pet-bar"),
            CodexThreadMenuRow(id: "thread-d", title: "Older thread", folderTitle: "codex-pet-bar")
        ]

        let entries = CodexThreadMenuEntries.build(
            rows: rows,
            runningThreadIDs: ["thread-a"],
            visibleRecentLimit: 3
        )

        #expect(entries == [
            .sectionHeader("Running"),
            .thread(rows[0]),
            .sectionHeader("Recent"),
            .thread(rows[0]),
            .thread(rows[1]),
            .thread(rows[2]),
            .more([rows[3]])
        ])
    }
}

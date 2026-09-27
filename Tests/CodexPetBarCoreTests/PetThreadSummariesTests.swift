import Foundation
import Testing
@testable import CodexPetBarCore

@Suite("Navigable thread summaries")
struct PetThreadSummariesTests {
    @Test("one parent and two child runs become one named navigable thread")
    func parentAndChildrenConsolidate() throws {
        let rows = [
            task("parent", title: "Improve the menu bar", status: .completed, time: 10, project: "pet-bar"),
            task("child-a", parent: "parent", status: .running, time: 30),
            task("child-b", parent: "parent", status: .running, time: 20),
        ]
        let summaries = PetThreadSummaries.consolidated(rows)
        let thread = try #require(summaries.first)

        #expect(summaries.count == 1)
        #expect(thread.id == "codex:parent")
        #expect(thread.sourceID == "parent")
        #expect(thread.navigationSourceID == "parent")
        #expect(thread.deepLinkURL == CodexThreadDeepLink.url(forThreadID: "parent"))
        #expect(thread.title == "Improve the menu bar")
        #expect(thread.project.name == "pet-bar")
        #expect(thread.status == .running)
        #expect(thread.updatedAt == Date(timeIntervalSince1970: 30))
    }

    @Test("attention wins over a more recently completed parent and running sibling")
    func childAttentionWins() throws {
        let summaries = PetThreadSummaries.consolidated([
            task("parent", title: "Ship the app", status: .completed, time: 50),
            task("working", parent: "parent", status: .running, time: 40),
            task("permission", parent: "parent", status: .waiting, time: 20, detail: "Approve the release upload"),
        ])
        let thread = try #require(summaries.first)

        #expect(thread.status == .waiting)
        #expect(thread.detail == "Approve the release upload")
        #expect(thread.updatedAt == Date(timeIntervalSince1970: 50))
    }

    @Test("completed children do not make a quiet parent run")
    func finishedChildrenStayQuiet() throws {
        let thread = try #require(PetThreadSummaries.consolidated([
            task("parent", title: "Finished work", status: .recent, time: 50),
            task("child-a", parent: "parent", status: .completed, time: 30),
            task("child-b", parent: "parent", status: .recent, time: 20),
        ]).first)

        #expect(thread.status == .completed)
        #expect(thread.title == "Finished work")
    }

    @Test("only the newest copy of a run contributes activity")
    func newerCompletionResolvesDuplicateFailure() throws {
        let thread = try #require(PetThreadSummaries.consolidated([
            task("child", parent: "parent", status: .failed, time: 10),
            task("child", parent: "parent", status: .completed, time: 20),
        ]).first)

        #expect(thread.status == .completed)
    }

    @Test("real parent metadata survives a newer generic duplicate")
    func parentTitleSurvivesGenericCopy() throws {
        let thread = try #require(PetThreadSummaries.consolidated([
            task("parent", title: "Fix keyboard navigation", status: .running, time: 10, project: "pet-bar"),
            task("parent", status: .running, time: 20),
            task("child", parent: "parent", title: "Implement child detail", status: .running, time: 30),
        ]).first)

        #expect(thread.title == "Fix keyboard navigation")
        #expect(thread.project.name == "pet-bar")
    }

    @Test("latest useful detail for the winning state beats generic activity")
    func meaningfulDetailsSurviveGenericUpdates() throws {
        let thread = try #require(PetThreadSummaries.consolidated([
            task("parent", title: "Review permissions", status: .waiting, time: 10,
                 detail: "Approve opening the project"),
            task("first-child", parent: "parent", status: .waiting, time: 20,
                 detail: "Approve running the integration test"),
            task("second-child", parent: "parent", status: .waiting, time: 30,
                 detail: "Waiting for permission"),
            task("third-child", parent: "parent", status: .running, time: 40,
                 detail: "A running summary must not describe the permission request"),
        ]).first)

        #expect(thread.status == .waiting)
        #expect(thread.detail == "Approve running the integration test")
    }

    @Test("missing parents use truthful project or canonical ID fallbacks")
    func missingParentUsesKnownContext() throws {
        let summaries = PetThreadSummaries.consolidated([
            task("worker-a", parent: "known-parent", title: "Do not rename the parent after this child",
                 status: .running, time: 10, project: "pet-bar"),
            task("worker-b", parent: "019f842c-c312-7332-afec-d21d912578b7", status: .running, time: 20),
        ])
        let known = try #require(summaries.first { $0.sourceID == "known-parent" })
        let unknown = try #require(summaries.first { $0.sourceID != "known-parent" })

        #expect(known.title == "Task in pet-bar")
        #expect(unknown.title == "Codex task · …912578b7")
        #expect(known.id == "codex:known-parent")
        #expect(unknown.deepLinkURL == CodexThreadDeepLink.url(forThreadID: unknown.sourceID))
    }

    @Test("provider identities and non-Codex child navigation remain independent")
    func providersRemainIndependent() {
        let claude = task("child", parent: "parent", provider: .claude, title: "Claude session",
                          status: .running, time: 20)
        let cursor = task("child", parent: "parent", provider: .cursor, title: "Cursor session",
                          status: .waiting, time: 30)
        let summaries = PetThreadSummaries.consolidated([
            task("parent", title: "Codex parent", status: .running, time: 10),
            task("child", parent: "parent", status: .running, time: 20),
            claude, cursor,
        ])

        #expect(summaries.count == 3)
        #expect(summaries.contains(claude))
        #expect(summaries.contains(cursor))
        #expect(Set(summaries.map(\.id)) == ["codex:parent", "claude:child", "cursor:child"])
    }

    @Test("non-Codex duplicate records keep the newest original destination")
    func nonCodexDuplicatesKeepNewest() {
        let old = task("session", parent: "old-parent", provider: .claude, status: .failed, time: 10)
        let current = task("session", parent: "new-parent", provider: .claude, status: .completed, time: 20)

        #expect(PetThreadSummaries.consolidated([old, current]) == [current])
    }

    @Test("separate Codex threads in one project remain separate")
    func sharedProjectDoesNotMergeThreads() {
        let summaries = PetThreadSummaries.consolidated([
            task("first-parent", title: "Task in progress", status: .running, time: 10, project: "pet-bar"),
            task("first-child", parent: "first-parent", status: .running, time: 20, project: "pet-bar"),
            task("second-child", parent: "second-parent", status: .running, time: 30, project: "pet-bar"),
        ])

        #expect(summaries.count == 2)
        #expect(Set(summaries.map(\.sourceID)) == ["first-parent", "second-parent"])
        #expect(summaries.first { $0.sourceID == "first-parent" }?.title == "Task in progress")
    }

    @Test("ordering is deterministic and retains all history")
    func deterministicOrderingWithoutHistoryLimit() {
        let history = (0..<120).map { task("history-\($0)", status: .recent, time: Double($0)) }
        let rows = history + [
            task("running", status: .running, time: 900),
            task("failed", status: .failed, time: 10),
            task("waiting-b", status: .waiting, time: 20),
            task("waiting-a", status: .waiting, time: 20),
            task("completed", status: .completed, time: 500),
        ]
        let summaries = PetThreadSummaries.consolidated(rows)

        #expect(summaries.count == rows.count)
        #expect(summaries.prefix(5).map(\.sourceID) == ["waiting-a", "waiting-b", "failed", "running", "completed"])
        #expect(PetThreadSummaries.consolidated(rows.reversed()) == summaries)
        #expect(PetThreadSummaries.consolidated(summaries) == summaries)
    }

    @Test("parent assignment identity is stable as children arrive and disappear")
    func canonicalIdentityStaysStable() throws {
        let child = task("child", parent: "parent", status: .running, time: 10)
        let parent = task("parent", title: "Named thread", status: .completed, time: 20)
        let before = try #require(PetThreadSummaries.consolidated([child]).first)
        let during = try #require(PetThreadSummaries.consolidated([child, parent]).first)
        let after = try #require(PetThreadSummaries.consolidated([parent]).first)

        #expect(before.id == during.id)
        #expect(during.id == after.id)
        #expect(after.id == "codex:parent")
    }

    private func task(_ sourceID: String, parent: String? = nil, provider: PetProvider = .codex,
                      title: String = "Codex task", status: PetTaskStatus, time: TimeInterval,
                      project: String? = nil, detail: String = "Working") -> PetTaskSummary {
        PetTaskSummary(sourceID: sourceID, navigationSourceID: parent, provider: provider,
            title: title, detail: detail, status: status,
            project: project.map { .derived(fromWorkspace: "/example/\($0)") } ?? .other,
            updatedAt: Date(timeIntervalSince1970: time),
            deepLinkURL: provider == .codex ? CodexThreadDeepLink.url(forThreadID: parent ?? sourceID) : nil)
    }
}

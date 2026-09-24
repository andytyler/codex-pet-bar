import Testing
@testable import CodexPetBarCore

@Suite("Codex thread floor dots")
struct CodexThreadDotMetricsTests {
    @Test("no running threads means no floor dots")
    func noRunningThreadsMeansNoFloorDots() {
        #expect(CodexThreadDotMetrics.floorDots(count: 0, playfieldWidth: 56, phase: 0).isEmpty)
        #expect(CodexThreadDotMetrics.floorDots(count: -2, playfieldWidth: 56, phase: 0).isEmpty)
        #expect(CodexThreadDotMetrics.floorDots(count: 2, playfieldWidth: 0, phase: 0).isEmpty)
    }

    @Test("floor dots match the running thread count")
    func floorDotsMatchTheRunningThreadCount() {
        let dots = CodexThreadDotMetrics.floorDots(count: 4, playfieldWidth: 56, phase: 0)

        #expect(dots.count == 4)
        #expect(dots.allSatisfy { $0.centerX >= 0 && $0.centerX <= 56 })
        #expect(dots.allSatisfy { $0.centerY > 0 })
        #expect(dots.allSatisfy { $0.diameter == CodexThreadDotMetrics.codexLogoDiameter })
    }

    @Test("minimum playfield keeps mixed provider flags individually readable")
    func minimumPlayfieldKeepsEveryVisibleFlag() {
        let width = CodexThreadDotMetrics.minimumPlayfieldWidth(count: 6)
        let dots = CodexThreadDotMetrics.floorDots(count: 6, playfieldWidth: width, phase: 0)

        #expect(dots.count == 6)
        #expect(dots.allSatisfy { $0.diameter >= 10 })
        #expect(CodexThreadDotMetrics.minimumPlayfieldWidth(count: 0) == 0)
    }

    @Test("minimum playfield retains the defensive render cap")
    func minimumPlayfieldRetainsRenderCap() {
        let capped = CodexThreadDotMetrics.minimumPlayfieldWidth(count: CodexThreadDotMetrics.maximumVisibleDotCount)
        let excessive = CodexThreadDotMetrics.minimumPlayfieldWidth(count: 10_000)

        #expect(excessive == capped)
    }

    @Test("attention scopes survive the defensive render cap")
    func attentionScopesSurviveRenderCap() {
        var scopes = (0..<CodexThreadDotMetrics.maximumVisibleDotCount + 4).map { index in
            CodexPetActiveScope(
                provider: index.isMultiple(of: 2) ? .codex : .claude,
                scopedIdentity: "running-\(index)",
                activity: .running
            )
        }
        let cursorFailure = CodexPetActiveScope(
            provider: .cursor,
            scopedIdentity: "cursor-failure",
            activity: .failed
        )
        let cursorReview = CodexPetActiveScope(
            provider: .cursor,
            scopedIdentity: "cursor-review",
            activity: .reviewing
        )
        scopes.append(contentsOf: [cursorFailure, cursorReview])

        let layout = CodexThreadDotMetrics.flagLayout(for: scopes)

        #expect(
            layout.visibleScopes.count
                == CodexThreadDotMetrics.maximumVisibleDotCount
                    - CodexThreadDotMetrics.overflowMarkerSlotCount
        )
        #expect(layout.visibleScopes.contains(cursorFailure))
        #expect(layout.visibleScopes.contains(cursorReview))
        #expect(layout.overflowCount == scopes.count - layout.visibleScopes.count)
        #expect(layout.renderedSlotCount == CodexThreadDotMetrics.maximumVisibleDotCount)
        #expect(layout.overflowActivity == .running)
    }

    @Test("overflow is explicit while work stays bounded")
    func overflowIsExplicitAndBounded() {
        let scopes = (0...CodexThreadDotMetrics.maximumVisibleDotCount).map { index in
            CodexPetActiveScope(
                provider: .codex,
                scopedIdentity: "scope-\(index)",
                activity: .running
            )
        }

        let layout = CodexThreadDotMetrics.flagLayout(for: scopes)

        #expect(layout.overflowCount == 3)
        #expect(layout.overflowMarkerSlotCount == 2)
        #expect(layout.renderedSlotCount == CodexThreadDotMetrics.maximumVisibleDotCount)
        #expect(layout.overflowActivity == .running)
    }

    @Test("overflow carries the highest-priority hidden attention state")
    func overflowCarriesHiddenAttention() {
        let reviewing = (0..<31).map { index in
            CodexPetActiveScope(
                provider: .codex,
                scopedIdentity: "reviewing-\(index)",
                activity: .reviewing
            )
        }
        let failed = (0..<3).map { index in
            CodexPetActiveScope(
                provider: .claude,
                scopedIdentity: "failed-\(index)",
                activity: .failed
            )
        }

        let reviewingOverflow = CodexThreadDotMetrics.flagLayout(for: reviewing + failed)
        let failedOverflow = CodexThreadDotMetrics.flagLayout(for: Array(reviewing.prefix(30)) + failed)

        #expect(reviewingOverflow.overflowActivity == .reviewing)
        #expect(failedOverflow.overflowActivity == .failed)
        #expect(reviewingOverflow.renderedSlotCount == CodexThreadDotMetrics.maximumVisibleDotCount)
        #expect(failedOverflow.renderedSlotCount == CodexThreadDotMetrics.maximumVisibleDotCount)
    }

    @Test("ordinary scope counts do not reserve overflow space")
    func ordinaryScopesDoNotReserveOverflowSpace() {
        let scopes = (0..<CodexThreadDotMetrics.maximumVisibleDotCount).map { index in
            CodexPetActiveScope(
                provider: .cursor,
                scopedIdentity: "scope-\(index)",
                activity: .running
            )
        }

        let layout = CodexThreadDotMetrics.flagLayout(for: scopes)

        #expect(layout.visibleScopes == scopes)
        #expect(layout.overflowCount == 0)
        #expect(layout.overflowMarkerSlotCount == 0)
        #expect(layout.overflowActivity == nil)
        #expect(layout.renderedSlotCount == CodexThreadDotMetrics.maximumVisibleDotCount)
    }

    @Test("floor dots bob vertically without horizontal drift")
    func floorDotsBobVerticallyWithoutHorizontalDrift() {
        let first = CodexThreadDotMetrics.floorDots(count: 3, playfieldWidth: 56, phase: 0)
        let later = CodexThreadDotMetrics.floorDots(count: 3, playfieldWidth: 56, phase: 1)

        #expect(first.map(\.centerX) == later.map(\.centerX))
        #expect(first.map(\.diameter) == later.map(\.diameter))
        #expect(first.map(\.centerY) != later.map(\.centerY))
    }

    @Test("very high thread counts have bounded render work")
    func highThreadCountsAreBounded() {
        let dots = CodexThreadDotMetrics.floorDots(count: 10_000, playfieldWidth: 102, phase: 0)

        #expect(dots.count == CodexThreadDotMetrics.maximumVisibleDotCount)
        #expect(dots.allSatisfy { $0.diameter >= 2 })
    }
}

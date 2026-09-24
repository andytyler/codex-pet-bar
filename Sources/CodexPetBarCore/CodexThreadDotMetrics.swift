import Foundation

public enum CodexThreadDotMetrics {
    public static let codexLogoDiameter: Double = 11.2
    public static let maximumVisibleDotCount = 32
    public static let overflowMarkerSlotCount = 2
    private static let horizontalPadding: Double = 10
    private static let minimumFlagStride: Double = 10.5

    /// Returns the compact width needed to keep one readable provider flag for
    /// every visible active scope. The visible-count cap bounds rendering for a
    /// corrupt or unexpectedly large event log.
    public static func minimumPlayfieldWidth(count: Int) -> Double {
        guard count > 0 else {
            return 0
        }

        let visibleCount = min(count, maximumVisibleDotCount)
        return horizontalPadding + (Double(visibleCount) * minimumFlagStride)
    }

    /// Keeps normal ordering for ordinary counts. If a damaged or unusually
    /// busy log exceeds the defensive draw cap, a compact overflow marker uses
    /// two slots and attention states win the remaining provider slots.
    public static func flagLayout(for scopes: [CodexPetActiveScope]) -> CodexThreadFlagLayout {
        guard scopes.count > maximumVisibleDotCount else {
            return CodexThreadFlagLayout(
                visibleScopes: scopes,
                overflowCount: 0,
                overflowMarkerSlotCount: 0,
                overflowActivity: nil
            )
        }

        let visibleScopeCount = maximumVisibleDotCount - overflowMarkerSlotCount
        let prioritizedScopes = scopes.enumerated()
            .sorted { lhs, rhs in
                let lhsPriority = visibilityPriority(lhs.element.activity)
                let rhsPriority = visibilityPriority(rhs.element.activity)
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                return lhs.offset < rhs.offset
            }

        let visibleScopes = prioritizedScopes
            .prefix(visibleScopeCount)
            .sorted { $0.offset < $1.offset }
            .map(\.element)
        let overflowActivity = prioritizedScopes
            .dropFirst(visibleScopeCount)
            .first?
            .element
            .activity

        return CodexThreadFlagLayout(
            visibleScopes: visibleScopes,
            overflowCount: scopes.count - visibleScopes.count,
            overflowMarkerSlotCount: overflowMarkerSlotCount,
            overflowActivity: overflowActivity
        )
    }

    /// Compatibility helper for callers that only need the selected scopes.
    public static func visibleScopes(_ scopes: [CodexPetActiveScope]) -> [CodexPetActiveScope] {
        flagLayout(for: scopes).visibleScopes
    }

    public static func floorDots(count: Int, playfieldWidth: Double, phase: Double) -> [CodexThreadDotMetric] {
        guard count > 0, playfieldWidth > 0 else {
            return []
        }

        let distinguishableDotCount = max(1, Int((playfieldWidth - horizontalPadding) / 2))
        let visibleCount = min(count, maximumVisibleDotCount, distinguishableDotCount)
        let diameter = min(codexLogoDiameter, max(2.0, (playfieldWidth - horizontalPadding) / Double(visibleCount)))
        let startX = 5 + (diameter / 2)
        let availableWidth = max(0, playfieldWidth - horizontalPadding - diameter)
        let spacing = visibleCount > 1 ? availableWidth / Double(visibleCount - 1) : 0

        return (0..<visibleCount).map { index in
            let offset = spacing * Double(index)
            let bob = sin(phase + (Double(index) * 1.7)) * 1.35
            return CodexThreadDotMetric(
                centerX: startX + offset,
                centerY: 4.4 + bob,
                diameter: diameter
            )
        }
    }

    private static func visibilityPriority(_ activity: CodexActivity) -> Int {
        switch activity {
        case .reviewing:
            0
        case .failed:
            1
        case .running:
            2
        case .listening:
            3
        case .idle:
            4
        }
    }
}

public struct CodexThreadFlagLayout: Equatable, Sendable {
    public let visibleScopes: [CodexPetActiveScope]
    public let overflowCount: Int
    public let overflowMarkerSlotCount: Int
    /// Highest-priority activity hidden behind the overflow marker.
    public let overflowActivity: CodexActivity?

    public var renderedSlotCount: Int {
        visibleScopes.count + overflowMarkerSlotCount
    }

    public init(
        visibleScopes: [CodexPetActiveScope],
        overflowCount: Int,
        overflowMarkerSlotCount: Int,
        overflowActivity: CodexActivity? = nil
    ) {
        self.visibleScopes = visibleScopes
        self.overflowCount = overflowCount
        self.overflowMarkerSlotCount = overflowMarkerSlotCount
        self.overflowActivity = overflowActivity
    }
}

public struct CodexThreadDotMetric: Equatable, Sendable {
    public let centerX: Double
    public let centerY: Double
    public let diameter: Double

    public init(centerX: Double, centerY: Double, diameter: Double) {
        self.centerX = centerX
        self.centerY = centerY
        self.diameter = diameter
    }
}

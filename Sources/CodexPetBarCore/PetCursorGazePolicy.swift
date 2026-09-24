import Foundation

public struct PetCursorGazeUpdate: Equatable, Sendable {
    public let headingIndex: Int?
    public let shouldRender: Bool

    public init(headingIndex: Int?, shouldRender: Bool) {
        self.headingIndex = headingIndex
        self.shouldRender = shouldRender
    }
}

public enum PetCursorGazePolicy {
    public static func shouldTrack(
        spriteVersionNumber: Int,
        activity: CodexActivity,
        hasActiveThreads: Bool,
        manualAnimationState: PetAnimationState?,
        hasReaction: Bool,
        approvalRequested: Bool,
        reduceMotion: Bool
    ) -> Bool {
        spriteVersionNumber == 2
            && activity == .idle
            && !hasActiveThreads
            && manualAnimationState == nil
            && !hasReaction
            && !approvalRequested
            && !reduceMotion
    }

    public static func update(
        x: Double,
        y: Double,
        previousHeadingIndex: Int?,
        deadzone: Double = 1
    ) -> PetCursorGazeUpdate {
        let headingIndex = PetAtlasMetadata.directionalFrame(
            x: x,
            y: y,
            deadzone: deadzone
        )?.headingIndex
        return PetCursorGazeUpdate(
            headingIndex: headingIndex,
            shouldRender: headingIndex != previousHeadingIndex
        )
    }

    public static func coalescingDelay(
        lastRenderTime: TimeInterval?,
        now: TimeInterval,
        minimumInterval: TimeInterval
    ) -> TimeInterval {
        guard
            let lastRenderTime,
            lastRenderTime.isFinite,
            now.isFinite,
            minimumInterval.isFinite,
            minimumInterval > 0
        else {
            return 0
        }

        return max(0, minimumInterval - max(0, now - lastRenderTime))
    }
}

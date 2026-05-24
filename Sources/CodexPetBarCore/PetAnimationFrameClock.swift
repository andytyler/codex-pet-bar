public struct PetAnimationFrameClock: Equatable, Sendable {
    public private(set) var frameIndex: Int
    private var elapsedMilliseconds: Double

    public init(frameIndex: Int = 0, elapsedMilliseconds: Double = 0) {
        self.frameIndex = max(0, frameIndex)
        self.elapsedMilliseconds = max(0, elapsedMilliseconds)
    }

    public mutating func reset() {
        frameIndex = 0
        elapsedMilliseconds = 0
    }

    public mutating func advanceAfterDisplay(
        deltaTime: Double,
        metadata: AnimationRowMetadata?,
        frameCount: Int
    ) {
        guard frameCount > 0 else {
            reset()
            return
        }

        frameIndex %= frameCount
        elapsedMilliseconds += max(0, deltaTime) * 1_000

        let duration = frameDurationMilliseconds(
            at: frameIndex,
            metadata: metadata,
            fallback: 140
        )

        guard elapsedMilliseconds >= duration else {
            return
        }

        elapsedMilliseconds -= duration
        frameIndex = (frameIndex + 1) % frameCount
    }

    private func frameDurationMilliseconds(
        at index: Int,
        metadata: AnimationRowMetadata?,
        fallback: Double
    ) -> Double {
        guard
            let metadata,
            metadata.frameDurationsMS.indices.contains(index)
        else {
            return fallback
        }

        return max(1, Double(metadata.frameDurationsMS[index]))
    }
}

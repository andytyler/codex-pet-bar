public struct PetRuntimeFrame: Equatable, Sendable {
    public let animationState: PetAnimationState
    public let frameIndex: Int
    public let positionX: Double
    public let scale: Double
    public let isApprovalPulseActive: Bool
    public let isApprovalPresentationActive: Bool

    public init(
        animationState: PetAnimationState,
        frameIndex: Int,
        positionX: Double,
        scale: Double,
        isApprovalPulseActive: Bool,
        isApprovalPresentationActive: Bool
    ) {
        self.animationState = animationState
        self.frameIndex = frameIndex
        self.positionX = positionX
        self.scale = scale
        self.isApprovalPulseActive = isApprovalPulseActive
        self.isApprovalPresentationActive = isApprovalPresentationActive
    }
}

public struct PetRuntime: Sendable {
    public private(set) var motion: PetMotion
    public private(set) var frameClock: PetAnimationFrameClock

    private var approvalPulseRemaining: Double
    private var approvalPulseElapsed: Double
    private var approvalPulseQueued: Bool
    private var lastAnimationState: PetAnimationState

    public init(
        playfieldWidth: Double,
        spriteWidth: Double,
        motionSpeed: Double = 18,
        frameIndex: Int = 0,
        animationState: PetAnimationState = .waiting
    ) {
        self.motion = PetMotion(playfieldWidth: playfieldWidth, spriteWidth: spriteWidth, speed: motionSpeed)
        self.frameClock = PetAnimationFrameClock(frameIndex: frameIndex)
        self.approvalPulseRemaining = 0
        self.approvalPulseElapsed = 0
        self.approvalPulseQueued = false
        self.lastAnimationState = animationState
    }

    public mutating func resetLayout(playfieldWidth: Double, spriteWidth: Double, motionSpeed: Double? = nil) {
        let speed = motionSpeed ?? motion.speed
        motion = PetMotion(playfieldWidth: playfieldWidth, spriteWidth: spriteWidth, speed: speed)
        frameClock.reset()
        lastAnimationState = .waiting
        approvalPulseRemaining = 0
        approvalPulseElapsed = 0
        approvalPulseQueued = false
    }

    public mutating func cancelApprovalPulse() {
        approvalPulseRemaining = 0
        approvalPulseElapsed = 0
        approvalPulseQueued = false
    }

    public mutating func tick(
        activity: CodexActivity,
        reactionState: PetAnimationState? = nil,
        approvalRequested: Bool,
        deltaTime: Double
    ) -> PetRuntimeFrame {
        if approvalRequested {
            approvalPulseQueued = true
        }

        let centeredForApproval = updateMotion(activity: activity, reactionState: reactionState, deltaTime: deltaTime)
        if approvalPulseQueued, centeredForApproval {
            approvalPulseQueued = false
            approvalPulseRemaining = Self.approvalPresentationDuration
            approvalPulseElapsed = 0
        } else if !approvalPulseQueued {
            let elapsed = max(0, deltaTime)
            approvalPulseRemaining = max(0, approvalPulseRemaining - elapsed)
            approvalPulseElapsed = min(
                Self.approvalCameraDuration,
                approvalPulseElapsed + elapsed
            )
        }

        let animationState = animationState(for: activity, reactionState: reactionState)
        if animationState != lastAnimationState {
            frameClock.reset()
            lastAnimationState = animationState
        }

        let metadata = PetAtlasMetadata.playbackRow(for: animationState)
        let frameCount = metadata?.usedColumns.count ?? 0
        frameClock.advanceAfterDisplay(deltaTime: deltaTime, metadata: metadata, frameCount: frameCount)

        return PetRuntimeFrame(
            animationState: animationState,
            frameIndex: frameClock.frameIndex,
            positionX: motion.positionX,
            scale: scaleForCurrentPulse(),
            isApprovalPulseActive: approvalPulseQueued || approvalPulseRemaining > 0,
            isApprovalPresentationActive: approvalPulseRemaining > 0
        )
    }

    private func animationState(for activity: CodexActivity, reactionState: PetAnimationState?) -> PetAnimationState {
        if approvalPulseQueued {
            return motion.animationState
        }

        if approvalPulseRemaining > 0 {
            return .waving
        }

        if let reactionState {
            return reactionState
        }

        switch activity {
        case .running:
            return motion.animationState
        default:
            return activity.animationState
        }
    }

    @discardableResult
    private mutating func updateMotion(
        activity: CodexActivity,
        reactionState: PetAnimationState?,
        deltaTime: Double
    ) -> Bool {
        if approvalPulseQueued || approvalPulseRemaining > 0 {
            return motion.advanceTowardCenter(deltaTime: deltaTime)
        }

        if reactionState != nil {
            return motion.advanceTowardCenter(deltaTime: deltaTime)
        }

        switch activity {
        case .running:
            if !motion.isWalking {
                motion.startWalking(direction: motion.direction)
            }
            motion.advance(deltaTime: deltaTime)
            return false
        case .reviewing:
            return motion.advanceTowardCenter(deltaTime: deltaTime)
        default:
            motion.stopWalking()
            return false
        }
    }

    private func scaleForCurrentPulse() -> Double {
        guard approvalPulseRemaining > 0 else {
            return 1
        }

        let linearProgress = min(
            1,
            max(0, approvalPulseElapsed / Self.approvalCameraDuration)
        )
        let easedProgress: Double
        if linearProgress < 0.5 {
            easedProgress = 4 * linearProgress * linearProgress * linearProgress
        } else {
            let inverse = -2 * linearProgress + 2
            easedProgress = 1 - ((inverse * inverse * inverse) / 2)
        }
        return 1 + ((Self.approvalCameraScale - 1) * easedProgress)
    }

    private static let approvalPresentationDuration = 2.4
    private static let approvalCameraDuration = 0.9
    private static let approvalCameraScale = 2.6
}

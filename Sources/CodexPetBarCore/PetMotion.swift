public enum PetDirection: Sendable {
    case left
    case right
}

public struct PetMotion: Sendable {
    public private(set) var positionX: Double
    public private(set) var direction: PetDirection
    public private(set) var isWalking: Bool

    public let playfieldWidth: Double
    public let spriteWidth: Double
    public var speed: Double

    public init(playfieldWidth: Double, spriteWidth: Double, speed: Double = 18) {
        self.playfieldWidth = playfieldWidth
        self.spriteWidth = spriteWidth
        self.speed = speed
        self.positionX = max(0, (playfieldWidth - spriteWidth) / 2)
        self.direction = .right
        self.isWalking = false
    }

    public var animationState: PetAnimationState {
        guard isWalking else {
            return .waiting
        }

        switch direction {
        case .left:
            return .runningLeft
        case .right:
            return .runningRight
        }
    }

    public static func tickerAnimationState(
        reachedTrailingEdge: Bool,
        runningThreadCount: Int
    ) -> PetAnimationState {
        if reachedTrailingEdge && runningThreadCount <= 0 {
            return .idle
        }

        return .runningRight
    }

    public mutating func startWalking(direction: PetDirection) {
        self.direction = direction
        isWalking = true
    }

    public mutating func stopWalking() {
        isWalking = false
    }

    public mutating func advance(deltaTime: Double) {
        guard isWalking else {
            return
        }

        let maxX = max(0, playfieldWidth - spriteWidth)
        let signedSpeed: Double = direction == .right ? speed : -speed
        var next = positionX + signedSpeed * deltaTime

        if next >= maxX {
            next = maxX
            direction = .left
        } else if next <= 0 {
            next = 0
            direction = .right
        }

        positionX = next
    }

    @discardableResult
    public mutating func advanceTowardTrailingEdge(deltaTime: Double, visibleFraction: Double = 1.0) -> Bool {
        let visibleFraction = min(1, max(0, visibleFraction))
        let maxX = max(0, playfieldWidth - (spriteWidth * visibleFraction))
        direction = .right

        guard positionX < maxX else {
            positionX = maxX
            isWalking = false
            return true
        }

        isWalking = true
        let next = positionX + max(0, speed * deltaTime)
        if next >= maxX {
            positionX = maxX
            isWalking = false
            return true
        }

        positionX = next
        return false
    }

    @discardableResult
    public mutating func advanceTowardCenter(deltaTime: Double, tolerance: Double = 0.25) -> Bool {
        let targetX = max(0, (playfieldWidth - spriteWidth) / 2)
        let distance = targetX - positionX
        let tolerance = max(0, tolerance)

        guard abs(distance) > tolerance else {
            positionX = targetX
            isWalking = false
            return true
        }

        direction = distance > 0 ? .right : .left
        isWalking = true

        let step = max(0, speed * deltaTime)
        guard step < abs(distance) else {
            positionX = targetX
            isWalking = false
            return true
        }

        positionX += direction == .right ? step : -step
        return false
    }
}

/// Invalidates an in-flight fade when either hover surface regains the pointer.
public struct PetHoverDismissalPolicy: Sendable {
    private var generation: UInt = 0
    public private(set) var isFading = false

    public init() {}

    public mutating func beginFade() -> UInt {
        generation &+= 1
        isFading = true
        return generation
    }

    @discardableResult
    public mutating func cancelFade() -> Bool {
        let wasFading = isFading
        generation &+= 1
        isFading = false
        return wasFading
    }

    public mutating func finishFade(_ token: UInt, pointerOwnsSurface: Bool) -> Bool {
        guard isFading, token == generation else { return false }
        isFading = false
        return !pointerOwnsSurface
    }
}

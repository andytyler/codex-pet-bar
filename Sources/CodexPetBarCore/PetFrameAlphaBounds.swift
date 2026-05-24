public struct PetFrameAlphaBounds: Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static func contentBounds(
        alpha: [UInt8],
        width: Int,
        height: Int,
        threshold: UInt8 = 0
    ) -> PetFrameAlphaBounds? {
        guard width > 0, height > 0, alpha.count >= width * height else {
            return nil
        }

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            for x in 0..<width {
                let alphaValue = alpha[y * width + x]
                guard alphaValue > threshold else {
                    continue
                }

                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else {
            return nil
        }

        return PetFrameAlphaBounds(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
    }

    public func padded(by padding: Int, withinWidth frameWidth: Int, height frameHeight: Int) -> PetFrameAlphaBounds {
        let padding = max(0, padding)
        let frameWidth = max(0, frameWidth)
        let frameHeight = max(0, frameHeight)
        let minX = max(0, x - padding)
        let minY = max(0, y - padding)
        let maxX = min(frameWidth, x + width + padding)
        let maxY = min(frameHeight, y + height + padding)

        return PetFrameAlphaBounds(
            x: minX,
            y: minY,
            width: max(0, maxX - minX),
            height: max(0, maxY - minY)
        )
    }

    public static func union(_ bounds: [PetFrameAlphaBounds]) -> PetFrameAlphaBounds? {
        guard let first = bounds.first else {
            return nil
        }

        var minX = first.x
        var minY = first.y
        var maxX = first.x + first.width
        var maxY = first.y + first.height

        for bound in bounds.dropFirst() {
            minX = min(minX, bound.x)
            minY = min(minY, bound.y)
            maxX = max(maxX, bound.x + bound.width)
            maxY = max(maxY, bound.y + bound.height)
        }

        return PetFrameAlphaBounds(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }
}

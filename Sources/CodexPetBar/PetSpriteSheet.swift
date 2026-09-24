import AppKit
import CodexPetBarCore

struct PetSpriteSheet {
    let framesByState: [PetAnimationState: [NSImage]]
    private let directionalFrames: [NSImage]

    init(package: PetPackage) throws {
        guard let sourceImage = NSImage(contentsOf: package.spritesheetURL) else {
            throw SpriteSheetError.cannotDecode(package.spritesheetURL.path)
        }

        var proposedRect = NSRect(origin: .zero, size: sourceImage.size)
        guard let cgImage = sourceImage.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            throw SpriteSheetError.cannotCreateCGImage(package.spritesheetURL.path)
        }

        guard let rowCount = PetAtlasMetadata.rowCount(
            forSpriteVersionNumber: package.spriteVersionNumber
        ) else {
            throw SpriteSheetError.unsupportedVersion(package.spriteVersionNumber)
        }

        let expectedWidth = PetAtlasMetadata.columns * PetAtlasMetadata.cellWidth
        let expectedHeight = rowCount * PetAtlasMetadata.cellHeight
        guard cgImage.width == expectedWidth, cgImage.height == expectedHeight else {
            throw SpriteSheetError.invalidDimensions(
                actualWidth: cgImage.width,
                actualHeight: cgImage.height,
                expectedWidth: expectedWidth,
                expectedHeight: expectedHeight
            )
        }

        let animationFrameCoordinates = PetAtlasMetadata.animationRows.flatMap { row in
            row.usedColumns.map { column in
                (row: row.rowIndex, column: column)
            }
        }
        let directionalFrameCoordinates: [(row: Int, column: Int)]
        if package.spriteVersionNumber == 2 {
            directionalFrameCoordinates = (0..<16).map { headingIndex in
                (
                    row: 9 + headingIndex / PetAtlasMetadata.columns,
                    column: headingIndex % PetAtlasMetadata.columns
                )
            }
        } else {
            directionalFrameCoordinates = []
        }

        let allFrameCoordinates = animationFrameCoordinates + directionalFrameCoordinates
        let cropRects = allFrameCoordinates.map { coordinate in
            Self.cropRect(row: coordinate.row, column: coordinate.column)
        }
        guard
            let materializedFrames = PetFrameRasterizer.materializeFrames(
                from: cgImage,
                cropRects: cropRects
            ),
            materializedFrames.count == allFrameCoordinates.count
        else {
            throw SpriteSheetError.cannotCreateCGImage(package.spritesheetURL.path)
        }

        var frameIndex = 0
        var framesByState: [PetAnimationState: [NSImage]] = [:]
        for row in PetAtlasMetadata.animationRows {
            let rowFrameCount = row.usedColumns.count
            let rowFrames = materializedFrames[frameIndex..<(frameIndex + rowFrameCount)]
                .map(Self.image(from:))
            framesByState[row.state] = rowFrames
            frameIndex += rowFrameCount
        }

        self.framesByState = framesByState
        self.directionalFrames = materializedFrames[frameIndex...].map(Self.image(from:))
    }

    func frames(for state: PetAnimationState) -> [NSImage] {
        framesByState[state] ?? framesByState[.idle] ?? []
    }

    func directionalFrame(x: Double, y: Double, deadzone: Double = 1) -> NSImage? {
        guard
            let frame = PetAtlasMetadata.directionalFrame(x: x, y: y, deadzone: deadzone),
            directionalFrames.indices.contains(frame.headingIndex)
        else {
            return nil
        }

        return directionalFrames[frame.headingIndex]
    }

    func directionalFrame(headingIndex: Int) -> NSImage? {
        guard directionalFrames.indices.contains(headingIndex) else {
            return nil
        }
        return directionalFrames[headingIndex]
    }

    private static func cropRect(row: Int, column: Int) -> CGRect {
        CGRect(
            x: column * PetAtlasMetadata.cellWidth,
            y: row * PetAtlasMetadata.cellHeight,
            width: PetAtlasMetadata.cellWidth,
            height: PetAtlasMetadata.cellHeight
        )
    }

    private static func image(from frame: CGImage) -> NSImage {
        let image = NSImage(
            cgImage: frame,
            size: NSSize(width: PetAtlasMetadata.cellWidth, height: PetAtlasMetadata.cellHeight)
        )
        image.isTemplate = false
        return image
    }
}

enum SpriteSheetError: LocalizedError {
    case cannotDecode(String)
    case cannotCreateCGImage(String)
    case unsupportedVersion(Int)
    case invalidDimensions(actualWidth: Int, actualHeight: Int, expectedWidth: Int, expectedHeight: Int)

    var errorDescription: String? {
        switch self {
        case .cannotDecode(let path):
            "Could not decode spritesheet at \(path)."
        case .cannotCreateCGImage(let path):
            "Could not create an image buffer for \(path)."
        case .unsupportedVersion(let version):
            "Unsupported pet sprite version \(version)."
        case let .invalidDimensions(actualWidth, actualHeight, expectedWidth, expectedHeight):
            "Spritesheet is \(actualWidth)x\(actualHeight), expected \(expectedWidth)x\(expectedHeight)."
        }
    }
}

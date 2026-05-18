import AppKit
import CodexPetBarCore

struct PetSpriteSheet {
    let framesByState: [PetAnimationState: [NSImage]]

    init(package: PetPackage) throws {
        guard let sourceImage = NSImage(contentsOf: package.spritesheetURL) else {
            throw SpriteSheetError.cannotDecode(package.spritesheetURL.path)
        }

        var proposedRect = NSRect(origin: .zero, size: sourceImage.size)
        guard let cgImage = sourceImage.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            throw SpriteSheetError.cannotCreateCGImage(package.spritesheetURL.path)
        }

        let expectedWidth = PetAtlasMetadata.columns * PetAtlasMetadata.cellWidth
        let expectedHeight = PetAtlasMetadata.rows * PetAtlasMetadata.cellHeight
        guard cgImage.width == expectedWidth, cgImage.height == expectedHeight else {
            throw SpriteSheetError.invalidDimensions(
                actualWidth: cgImage.width,
                actualHeight: cgImage.height,
                expectedWidth: expectedWidth,
                expectedHeight: expectedHeight
            )
        }

        var framesByState: [PetAnimationState: [NSImage]] = [:]
        for row in PetAtlasMetadata.animationRows {
            let frames = row.usedColumns.compactMap { column -> NSImage? in
                let cropRect = CGRect(
                    x: column * PetAtlasMetadata.cellWidth,
                    y: row.rowIndex * PetAtlasMetadata.cellHeight,
                    width: PetAtlasMetadata.cellWidth,
                    height: PetAtlasMetadata.cellHeight
                )
                guard let frame = cgImage.cropping(to: cropRect) else {
                    return nil
                }
                let image = NSImage(
                    cgImage: frame,
                    size: NSSize(
                        width: PetAtlasMetadata.cellWidth,
                        height: PetAtlasMetadata.cellHeight
                    )
                )
                image.isTemplate = false
                return image
            }

            if !frames.isEmpty {
                framesByState[row.state] = frames
            }
        }

        self.framesByState = framesByState
    }

    func frames(for state: PetAnimationState) -> [NSImage] {
        framesByState[state] ?? framesByState[.idle] ?? []
    }
}

enum SpriteSheetError: LocalizedError {
    case cannotDecode(String)
    case cannotCreateCGImage(String)
    case invalidDimensions(actualWidth: Int, actualHeight: Int, expectedWidth: Int, expectedHeight: Int)

    var errorDescription: String? {
        switch self {
        case .cannotDecode(let path):
            "Could not decode spritesheet at \(path)."
        case .cannotCreateCGImage(let path):
            "Could not create an image buffer for \(path)."
        case let .invalidDimensions(actualWidth, actualHeight, expectedWidth, expectedHeight):
            "Spritesheet is \(actualWidth)x\(actualHeight), expected \(expectedWidth)x\(expectedHeight)."
        }
    }
}

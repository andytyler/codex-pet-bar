import AppKit
import CodexPetBarCore
import ImageIO
import SwiftUI

/// Small, independently decoded portraits. Loading a panel never retains a whole
/// atlas per task or starts another animation timer.
@MainActor
enum PetPortraits {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 48
        return cache
    }()

    static func image(for pet: PetPackage) -> NSImage? {
        let key = "\(pet.spritesheetURL.path):\(pet.spriteVersionNumber)" as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let source = CGImageSourceCreateWithURL(pet.spritesheetURL as CFURL, nil),
              let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let frame = PetFrameRasterizer.materializeFrames(from: atlas, cropRects: [
                CGRect(x: 0, y: 0, width: PetAtlasMetadata.cellWidth, height: PetAtlasMetadata.cellHeight)
              ])?.first,
              let context = CGContext(data: nil, width: frame.width, height: frame.height,
                  bitsPerComponent: 8, bytesPerRow: frame.width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(frame, in: CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self),
              let decoded = context.makeImage() else { return nil }
        let alpha = (0..<(frame.width * frame.height)).map { bytes[$0 * 4 + 3] }
        let bounds = PetFrameAlphaBounds.contentBounds(alpha: alpha, width: frame.width, height: frame.height)?
            .padded(by: 3, withinWidth: frame.width, height: frame.height)
        let portrait = bounds.flatMap {
            decoded.cropping(to: CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height))
        } ?? decoded
        let image = NSImage(cgImage: portrait, size: NSSize(width: portrait.width, height: portrait.height))
        cache.setObject(image, forKey: key)
        return image
    }
}

struct PetPortraitView: View {
    let pet: PetPackage?
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let pet, let image = PetPortraits.image(for: pet) {
                Image(nsImage: image).resizable().interpolation(.none).scaledToFit()
            } else {
                Image(systemName: "pawprint.fill")
                    .resizable().scaledToFit().padding(size * 0.22)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

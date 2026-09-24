import CoreGraphics

/// Materializes independently backed sprite frames from a potentially lazy image source.
///
/// ImageIO-backed formats such as WebP can otherwise retain their decoder through
/// `CGImage.cropping(to:)`. Drawing those crops later may decode the source atlas on
/// every animation tick. This helper decodes the atlas once, then copies only the
/// requested cells into independent raw bitmap providers.
public enum PetFrameRasterizer {
    public static func materializeFrames(
        from sourceImage: CGImage,
        cropRects: [CGRect]
    ) -> [CGImage]? {
        guard !cropRects.isEmpty else {
            return []
        }

        let colorSpace = compatibleRGBColorSpace(for: sourceImage)
        guard
            let atlasContext = makeBitmapContext(
                width: sourceImage.width,
                height: sourceImage.height,
                colorSpace: colorSpace
            )
        else {
            return nil
        }

        configurePixelArtDrawing(atlasContext)
        atlasContext.draw(
            sourceImage,
            in: CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height)
        )

        guard let decodedAtlas = atlasContext.makeImage() else {
            return nil
        }

        let atlasBounds = CGRect(
            x: 0,
            y: 0,
            width: decodedAtlas.width,
            height: decodedAtlas.height
        )
        var frames: [CGImage] = []
        frames.reserveCapacity(cropRects.count)

        for cropRect in cropRects {
            let integralCropRect = cropRect.integral
            guard
                cropRect == integralCropRect,
                cropRect.width > 0,
                cropRect.height > 0,
                atlasBounds.contains(cropRect),
                let croppedFrame = decodedAtlas.cropping(to: cropRect),
                let frameContext = makeBitmapContext(
                    width: Int(cropRect.width),
                    height: Int(cropRect.height),
                    colorSpace: colorSpace
                )
            else {
                return nil
            }

            configurePixelArtDrawing(frameContext)
            frameContext.draw(
                croppedFrame,
                in: CGRect(origin: .zero, size: cropRect.size)
            )
            guard let frame = frameContext.makeImage() else {
                return nil
            }
            frames.append(frame)
        }

        return frames
    }

    private static func compatibleRGBColorSpace(for image: CGImage) -> CGColorSpace {
        if let sourceColorSpace = image.colorSpace, sourceColorSpace.model == .rgb {
            return sourceColorSpace
        }

        return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    private static func makeBitmapContext(
        width: Int,
        height: Int,
        colorSpace: CGColorSpace
    ) -> CGContext? {
        guard width > 0, height > 0 else {
            return nil
        }

        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func configurePixelArtDrawing(_ context: CGContext) {
        context.setBlendMode(.copy)
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        context.setAllowsAntialiasing(false)
    }
}

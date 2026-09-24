import CoreGraphics
import Testing
@testable import CodexPetBarCore

@Suite("Pet frame rasterizer")
struct PetFrameRasterizerTests {
    @Test("Frames have independent providers and preserve RGBA pixels")
    func independentMaterializedFrames() throws {
        let source = try #require(makeTwoColorSourceImage())
        let frames = try #require(
            PetFrameRasterizer.materializeFrames(
                from: source,
                cropRects: [
                    CGRect(x: 0, y: 0, width: 2, height: 2),
                    CGRect(x: 2, y: 0, width: 2, height: 2)
                ]
            )
        )
        #expect(frames.count == 2)

        let sourceProvider = try #require(source.dataProvider)
        let firstProvider = try #require(frames[0].dataProvider)
        let secondProvider = try #require(frames[1].dataProvider)
        #expect(ObjectIdentifier(firstProvider) != ObjectIdentifier(sourceProvider))
        #expect(ObjectIdentifier(secondProvider) != ObjectIdentifier(sourceProvider))
        #expect(ObjectIdentifier(firstProvider) != ObjectIdentifier(secondProvider))

        #expect(frames[0].width == 2)
        #expect(frames[0].height == 2)
        #expect(frames[1].width == 2)
        #expect(frames[1].height == 2)
        #expect(firstPixel(of: frames[0]) == [128, 0, 0, 128])
        #expect(firstPixel(of: frames[1]) == [0, 255, 0, 255])
    }

    @Test("Vertical crops retain their top-to-bottom ordering")
    func verticalCropOrientation() throws {
        let source = try #require(makeVerticalSourceImage())
        let cropRects = [
            CGRect(x: 0, y: 0, width: 2, height: 2),
            CGRect(x: 0, y: 2, width: 2, height: 2)
        ]
        let directCrops = try cropRects.map { rect in
            try #require(source.cropping(to: rect))
        }
        let materializedFrames = try #require(
            PetFrameRasterizer.materializeFrames(from: source, cropRects: cropRects)
        )

        let directFirstRegion = try #require(rgbaPixels(of: directCrops[0]))
        let directSecondRegion = try #require(rgbaPixels(of: directCrops[1]))
        #expect(directFirstRegion != directSecondRegion)
        #expect(rgbaPixels(of: materializedFrames[0]) == directFirstRegion)
        #expect(rgbaPixels(of: materializedFrames[1]) == directSecondRegion)
    }

    @Test("Semitransparent pixels composite identically after materialization")
    func semitransparentComposition() throws {
        let source = try #require(makeTwoColorSourceImage())
        let cropRect = CGRect(x: 0, y: 0, width: 2, height: 2)
        let directCrop = try #require(source.cropping(to: cropRect))
        let materializedFrame = try #require(
            PetFrameRasterizer.materializeFrames(from: source, cropRects: [cropRect])?.first
        )
        let opaqueBackground = try #require(
            CGColor(
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                components: [0.1, 0.3, 0.8, 1]
            )
        )

        #expect(
            compositedPixels(of: materializedFrame, over: opaqueBackground)
                == compositedPixels(of: directCrop, over: opaqueBackground)
        )
    }

    @Test("Invalid crop requests fail without partial output")
    func invalidCropRects() throws {
        let source = try #require(makeTwoColorSourceImage())

        #expect(
            PetFrameRasterizer.materializeFrames(
                from: source,
                cropRects: [CGRect(x: 3, y: 0, width: 2, height: 2)]
            ) == nil
        )
        #expect(
            PetFrameRasterizer.materializeFrames(
                from: source,
                cropRects: [CGRect(x: 0.5, y: 0, width: 2, height: 2)]
            ) == nil
        )
    }

    @Test("An empty request does not allocate frames")
    func emptyCropRects() throws {
        let source = try #require(makeTwoColorSourceImage())
        let frames = try #require(
            PetFrameRasterizer.materializeFrames(from: source, cropRects: [])
        )

        #expect(frames.isEmpty)
    }

    private func makeTwoColorSourceImage() -> CGImage? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: 4,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 16,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setBlendMode(.copy)
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 0.5)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        context.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
        context.fill(CGRect(x: 2, y: 0, width: 2, height: 2))
        return context.makeImage()
    }

    private func makeVerticalSourceImage() -> CGImage? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: 2,
            height: 4,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setBlendMode(.copy)
        context.setFillColor(red: 0, green: 0.2, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        context.setFillColor(red: 1, green: 0.8, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 2, width: 2, height: 2))
        return context.makeImage()
    }

    private func firstPixel(of image: CGImage) -> [UInt8]? {
        rgbaPixels(of: image, outputWidth: 1, outputHeight: 1)
    }

    private func rgbaPixels(
        of image: CGImage,
        outputWidth: Int? = nil,
        outputHeight: Int? = nil
    ) -> [UInt8]? {
        let width = outputWidth ?? image.width
        let height = outputHeight ?? image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setBlendMode(.copy)
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    private func compositedPixels(of image: CGImage, over background: CGColor) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setBlendMode(.copy)
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.setBlendMode(.normal)
        context.interpolationQuality = .none
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
        return pixels
    }
}

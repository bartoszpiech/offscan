import Testing
import CoreGraphics
@testable import FlatlyCore

struct ThumbnailGeneratorTests {
    @Test func defaultMaxDimensionIs400() throws {
        let image = Synthetic.redCornerImage(width: 2000, height: 1500, square: 400)
        let thumb = try ThumbnailGenerator().thumbnail(for: image)
        #expect(thumb.width == 400 && thumb.height == 300)
        #expect(Bitmap(thumb)[10, 10].isRed)
    }

    @Test func customMaxDimensionKeepsAspect() throws {
        let image = Synthetic.image(width: 1000, height: 3000, background: Synthetic.gray(0.3))
        let thumb = try ThumbnailGenerator().thumbnail(for: image, maxDimension: 150)
        #expect(thumb.width == 50 && thumb.height == 150)
    }

    @Test func smallImagesAreNotUpscaled() throws {
        let image = Synthetic.image(width: 120, height: 90, background: Synthetic.gray(0.3))
        let thumb = try ThumbnailGenerator().thumbnail(for: image)
        #expect(thumb.width == 120 && thumb.height == 90)
    }
}

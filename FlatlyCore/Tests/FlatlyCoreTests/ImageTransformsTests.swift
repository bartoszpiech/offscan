import Testing
import CoreGraphics
@testable import FlatlyCore

struct ImageTransformsTests {
    let transforms = ImageTransforms()
    let source = Synthetic.redCornerImage(width: 200, height: 100)

    @Test func noneReturnsInput() throws {
        let out = try transforms.rotate(source, by: .none)
        #expect(out === source)
    }

    @Test func quarterSwapsDimensionsAndRotatesClockwise() throws {
        let out = try transforms.rotate(source, by: .quarter)
        #expect(out.width == 100 && out.height == 200)
        let bmp = Bitmap(out)
        // Top-left corner moves to the top-right on a clockwise quarter turn.
        #expect(bmp[out.width - 20, 20].isRed)
        #expect(!bmp[20, 20].isRed)
        #expect(!bmp[20, out.height - 20].isRed)
        #expect(!bmp[out.width - 20, out.height - 20].isRed)
    }

    @Test func halfKeepsDimensionsAndMovesToBottomRight() throws {
        let out = try transforms.rotate(source, by: .half)
        #expect(out.width == 200 && out.height == 100)
        let bmp = Bitmap(out)
        #expect(bmp[out.width - 20, out.height - 20].isRed)
        #expect(!bmp[20, 20].isRed)
    }

    @Test func threeQuartersMovesToBottomLeft() throws {
        let out = try transforms.rotate(source, by: .threeQuarters)
        #expect(out.width == 100 && out.height == 200)
        let bmp = Bitmap(out)
        #expect(bmp[20, out.height - 20].isRed)
        #expect(!bmp[out.width - 20, 20].isRed)
    }

    @Test func rotationIsLossless() throws {
        var image = source
        for _ in 0..<4 { image = try transforms.rotate(image, by: .quarter) }
        #expect(Bitmap(image).bytes == Bitmap(source).bytes)
    }

    @Test func cropProducesExactPixelSize() throws {
        let image = Synthetic.redCornerImage(width: 1000, height: 800)
        let out = try transforms.crop(image, to: CGRect(x: 0.1, y: 0.25, width: 0.5, height: 0.5))
        #expect(out.width == 500 && out.height == 400)
    }

    @Test func cropUsesTopLeftOrigin() throws {
        let image = Synthetic.redCornerImage(width: 1000, height: 800, square: 100)
        let top = try transforms.crop(image, to: CGRect(x: 0, y: 0, width: 0.2, height: 0.2))
        #expect(Bitmap(top)[10, 10].isRed)
        let bottom = try transforms.crop(image, to: CGRect(x: 0, y: 0.8, width: 0.2, height: 0.2))
        #expect(!Bitmap(bottom)[10, 10].isRed)
    }

    @Test func resizedRespectsMaxDimensionAndAspect() throws {
        let image = Synthetic.image(width: 3000, height: 1000, background: Synthetic.gray(0.5))
        let out = try transforms.resized(image, maxDimension: 600)
        #expect(out.width == 600 && out.height == 200)

        let tall = Synthetic.image(width: 900, height: 1600, background: Synthetic.gray(0.5))
        let outTall = try transforms.resized(tall, maxDimension: 800)
        #expect(outTall.height == 800 && outTall.width == 450)
    }

    @Test func resizedReturnsInputWhenSmallEnough() throws {
        let image = Synthetic.image(width: 300, height: 200, background: Synthetic.gray(0.5))
        #expect(try transforms.resized(image, maxDimension: 300) === image)
    }
}

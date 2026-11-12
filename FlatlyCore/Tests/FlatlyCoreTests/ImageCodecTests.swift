import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import FlatlyCore

struct ImageCodecTests {
    let codec = ImageCodec()

    /// Encodes `image` as JPEG with an EXIF orientation tag.
    private func jpeg(_ image: CGImage, orientation: Int) throws -> Data {
        let data = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(data as CFMutableData, "public.jpeg" as CFString, 1, nil))
        let props: [CFString: Any] = [kCGImagePropertyOrientation: orientation, kCGImageDestinationLossyCompressionQuality: 0.95]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        return data as Data
    }

    @Test func decodeAppliesExifOrientation() throws {
        // Stored 300×200 with red in the stored top-left. Orientation 6 = display rotated 90° CW,
        // so the upright image is 200×300 with red in the top-right.
        let stored = Synthetic.redCornerImage(width: 300, height: 200, square: 60)
        let data = try jpeg(stored, orientation: 6)

        let full = try codec.decode(data)
        #expect(full.width == 200 && full.height == 300)
        let bmp = Bitmap(full)
        #expect(bmp[full.width - 20, 20].isRed)
        #expect(!bmp[20, 20].isRed)

        let small = try codec.decode(data, maxDimension: 150)
        #expect(small.width == 100 && small.height == 150)
        let smallBmp = Bitmap(small)
        #expect(smallBmp[small.width - 10, 10].isRed)
        #expect(!smallBmp[10, 10].isRed)
    }

    @Test func decodeDoesNotUpscale() throws {
        let data = try codec.pngData(Synthetic.redCornerImage(width: 120, height: 80))
        let image = try codec.decode(data, maxDimension: 4000)
        #expect(image.width == 120 && image.height == 80)
    }

    @Test func pngRoundTripIsExact() throws {
        let image = Synthetic.image(width: 64, height: 48) { ctx in
            for y in 0..<48 {
                for x in 0..<64 {
                    ctx.setFillColor(CGColor(srgbRed: CGFloat(x * 4) / 255, green: CGFloat(y * 5) / 255, blue: CGFloat((x * y) % 256) / 255, alpha: 1))
                    ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        let decoded = try codec.decode(codec.pngData(image))
        #expect(decoded.width == 64 && decoded.height == 48)
        #expect(Bitmap(decoded).bytes == Bitmap(image).bytes)
    }

    @Test func jpegRoundTripKeepsSize() throws {
        let image = Synthetic.redCornerImage(width: 320, height: 240)
        let data = try codec.jpegData(image, quality: 0.8)
        #expect(data.starts(with: [0xFF, 0xD8]))
        let decoded = try codec.decode(data)
        #expect(decoded.width == 320 && decoded.height == 240)
        #expect(Bitmap(decoded)[10, 10].isRed)
    }

    @Test func garbageThrows() {
        #expect(throws: FlatlyCoreError.self) { try codec.decode(Data([1, 2, 3, 4])) }
    }

    @Test func decodesFixtureUpright() throws {
        let name = try #require(Fixtures.names.first)
        let image = try Fixtures.photo(name, maxDimension: 1000)
        #expect(max(image.width, image.height) == 1000)
    }

    // MARK: Focal length

    @Test func focalLengthRoundTripsThroughJPEG() throws {
        let image = Synthetic.redCornerImage(width: 400, height: 300)
        let data = try codec.jpegData(image, quality: 0.9, focalLength35mm: 26)
        #expect(codec.focalLength35mm(of: data) == 26)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(props[kCGImagePropertyGPSDictionary] == nil)
    }

    @Test func focalLengthIgnoredWithoutExifOrForCroppedFrame() throws {
        let plain = try codec.jpegData(Synthetic.redCornerImage(width: 400, height: 300), quality: 0.9)
        #expect(codec.focalLength35mm(of: plain) == nil)
        let cropped = try codec.jpegData(Synthetic.redCornerImage(width: 300, height: 200), quality: 0.9, focalLength35mm: 26)
        #expect(codec.focalLength35mm(of: cropped) == nil)
    }

    // MARK: Multi-page TIFF

    /// A 3-page TIFF: 100×50, then 60×80 stored with EXIF orientation 6 (upright 80×60), then 30×30.
    private func multiPageTIFF() throws -> Data {
        let data = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(data as CFMutableData, "public.tiff" as CFString, 3, nil))
        CGImageDestinationAddImage(dest, Synthetic.redCornerImage(width: 100, height: 50, square: 10), nil)
        CGImageDestinationAddImage(dest, Synthetic.redCornerImage(width: 60, height: 80, square: 10), [kCGImagePropertyOrientation: 6] as CFDictionary)
        CGImageDestinationAddImage(dest, Synthetic.redCornerImage(width: 30, height: 30, square: 10), nil)
        #expect(CGImageDestinationFinalize(dest))
        return data as Data
    }

    @Test func multiPageTIFFPageCount() throws {
        #expect(codec.pageCount(try multiPageTIFF()) == 3)
    }

    @Test func decodesEachTIFFPage() throws {
        let tiff = try multiPageTIFF()
        let first = try codec.decode(tiff, index: 0)
        #expect(first.width == 100 && first.height == 50)
        let second = try codec.decode(tiff, index: 1)
        #expect(second.width == 80 && second.height == 60)
        let small = try codec.decode(tiff, index: 1, maxDimension: 40)
        #expect(small.width == 40 && small.height == 30)
        let third = try codec.decode(tiff, index: 2)
        #expect(third.width == 30 && third.height == 30)
    }

    @Test func decodeRejectsOutOfRangeIndex() throws {
        let tiff = try multiPageTIFF()
        #expect(throws: FlatlyCoreError.self) { try codec.decode(tiff, index: 3) }
        #expect(throws: FlatlyCoreError.self) { try codec.decode(tiff, index: -1) }
    }

    @Test func pageCountIsOneForSinglePageAndNonTIFFSequences() throws {
        let image = Synthetic.redCornerImage(width: 40, height: 30)
        #expect(codec.pageCount(try codec.pngData(image)) == 1)
        #expect(codec.pageCount(try codec.jpegData(image, quality: 0.9)) == 1)
        let gif = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(gif as CFMutableData, "com.compuserve.gif" as CFString, 2, nil))
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        #expect(codec.pageCount(gif as Data) == 1)
    }

    @Test func pageCountZeroForGarbage() {
        #expect(codec.pageCount(Data([1, 2, 3, 4])) == 0)
    }

    @Test func pageCountFromURL() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).tiff")
        defer { try? FileManager.default.removeItem(at: url) }
        try multiPageTIFF().write(to: url)
        #expect(codec.pageCount(contentsOf: url) == 3)
        let third = try codec.decode(contentsOf: url, index: 2)
        #expect(third.width == 30 && third.height == 30)
    }
}

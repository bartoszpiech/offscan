import Testing
import Foundation
import CoreGraphics
@testable import FlatlyCore

struct PerspectiveCorrectorTests {
    @Test func flattensSkewedWhiteSheet() throws {
        let width = 1000, height = 800
        // Pixel corners, bottom-left origin (CoreGraphics context space).
        let tl = CGPoint(x: 180, y: 650), tr = CGPoint(x: 820, y: 700)
        let br = CGPoint(x: 880, y: 120), bl = CGPoint(x: 120, y: 180)
        let image = Synthetic.image(width: width, height: height, background: Synthetic.gray(0.1)) { ctx in
            ctx.setFillColor(Synthetic.gray(1))
            ctx.move(to: tl); ctx.addLine(to: tr); ctx.addLine(to: br); ctx.addLine(to: bl)
            ctx.closePath()
            ctx.fillPath()
        }
        func n(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x / CGFloat(width), y: p.y / CGFloat(height)) }
        let quad = Quadrilateral(topLeft: n(tl), topRight: n(tr), bottomRight: n(br), bottomLeft: n(bl))

        let out = try PerspectiveCorrector().correct(image, to: quad)
        // Size follows the average edge lengths.
        let expectedWidth = (hypot(tr.x - tl.x, tr.y - tl.y) + hypot(br.x - bl.x, br.y - bl.y)) / 2
        let expectedHeight = (hypot(tl.x - bl.x, tl.y - bl.y) + hypot(tr.x - br.x, tr.y - br.y)) / 2
        #expect(abs(CGFloat(out.width) - expectedWidth) <= 2)
        #expect(abs(CGFloat(out.height) - expectedHeight) <= 2)

        let bright = Bitmap(out).fraction { $0.luminance > 200 }
        #expect(bright >= 0.97, "bright fraction \(bright)")
    }

    @Test func rejectsNonConvexQuad() {
        let image = Synthetic.image(width: 100, height: 100, background: Synthetic.gray(1))
        let bowtie = Quadrilateral(topLeft: CGPoint(x: 0, y: 1), topRight: CGPoint(x: 1, y: 0), bottomRight: CGPoint(x: 1, y: 1), bottomLeft: CGPoint(x: 0, y: 0))
        #expect(throws: FlatlyCoreError.invalidQuadrilateral) {
            try PerspectiveCorrector().correct(image, to: bowtie)
        }
    }

    @Test func fullFrameKeepsImage() throws {
        let image = Synthetic.redCornerImage(width: 400, height: 300)
        let out = try PerspectiveCorrector().correct(image, to: .fullFrame)
        #expect(out.width == 400 && out.height == 300)
        let bmp = Bitmap(out)
        #expect(bmp[10, 10].isRed)
        #expect(!bmp[390, 290].isRed)
        #expect(bmp[390, 290].luminance > 240)
    }

    // MARK: Focal length (aspect ratio of pages shot at an angle)

    private static let imageWidth = 756.0, imageHeight = 1008.0
    private static let a4Aspect = 297.0 / 210.0

    /// Normalised bottom-left-origin quad of an A4 sheet (0.210 × 0.297 m) 0.40 m in front of a
    /// pinhole camera with the given 35 mm-equivalent focal length, tilted by `pitch` (about the
    /// horizontal axis) and `yaw` (about the vertical axis), shifted by `offset` metres.
    private static func projectedA4(f35: Double, pitch: Double, yaw: Double = 0, offset: (x: Double, y: Double) = (0, 0)) -> Quadrilateral {
        let w = imageWidth, h = imageHeight
        let fPx = f35 * hypot(w, h) / 43.27
        let p = pitch * .pi / 180, q = yaw * .pi / 180
        func project(_ sx: Double, _ sy: Double) -> CGPoint {
            // Sheet plane: x right, y down. Rotate about x (pitch), then about y (yaw).
            let y1 = sy * cos(p), z1 = sy * sin(p)
            let x2 = sx * cos(q) + z1 * sin(q), z2 = -sx * sin(q) + z1 * cos(q)
            let X = x2 + offset.x, Y = y1 + offset.y, Z = z2 + 0.40
            let u = w / 2 + fPx * X / Z, v = h / 2 + fPx * Y / Z   // image y points down
            return CGPoint(x: u / w, y: 1 - v / h)
        }
        let hw = 0.105, hh = 0.1485
        return Quadrilateral(topLeft: project(-hw, -hh), topRight: project(hw, -hh), bottomRight: project(hw, hh), bottomLeft: project(-hw, hh))
    }

    private static var imageSize: CGSize { CGSize(width: imageWidth, height: imageHeight) }

    private static func averageEdgeSize(_ quad: Quadrilateral) -> CGSize {
        PerspectiveCorrector.targetSize(for: quad.scaled(to: imageSize), imageSize: imageSize, focalLength35mm: nil)
    }

    @Test func tiltedA4WithFocalLengthKeepsA4Aspect() throws {
        let quad = Self.projectedA4(f35: 26, pitch: 30, offset: (0.02, -0.03))
        let image = Synthetic.image(width: Int(Self.imageWidth), height: Int(Self.imageHeight), background: Synthetic.gray(1))
        let average = Self.averageEdgeSize(quad)

        let plain = try PerspectiveCorrector().correct(image, to: quad)
        let plainAspect = Double(plain.height) / Double(plain.width)
        #expect(abs(plainAspect - Self.a4Aspect) / Self.a4Aspect > 0.06, "average edges squash a tilted page: \(plainAspect)")
        #expect(abs(CGFloat(plain.width) - average.width) <= 2 && abs(CGFloat(plain.height) - average.height) <= 2)

        let corrected = try PerspectiveCorrector().correct(image, to: quad, focalLength35mm: 26)
        let aspect = Double(corrected.height) / Double(corrected.width)
        #expect(abs(aspect - Self.a4Aspect) <= 0.02, "aspect \(aspect)")
        #expect(CGFloat(corrected.width) >= average.width - 1 && CGFloat(corrected.height) >= average.height - 1)
    }

    @Test func yawTiltWidensInsteadOfShrinking() {
        let quad = Self.projectedA4(f35: 26, pitch: 0, yaw: 30)
        let average = Self.averageEdgeSize(quad)
        let size = PerspectiveCorrector.targetSize(for: quad.scaled(to: Self.imageSize), imageSize: Self.imageSize, focalLength35mm: 26)
        let aspect = Double(size.height / size.width)
        #expect(abs(aspect - Self.a4Aspect) <= 0.02, "aspect \(aspect)")
        #expect(abs(size.height - average.height) <= 2)
    }

    @Test func parallelQuadIgnoresFocalLength() {
        let rect = Quadrilateral(topLeft: CGPoint(x: 0.2, y: 0.8), topRight: CGPoint(x: 0.7, y: 0.8), bottomRight: CGPoint(x: 0.7, y: 0.1), bottomLeft: CGPoint(x: 0.2, y: 0.1))
        for quad in [rect, Quadrilateral.fullFrame] {
            let px = quad.scaled(to: Self.imageSize)
            let plain = PerspectiveCorrector.targetSize(for: px, imageSize: Self.imageSize, focalLength35mm: nil)
            let focal = PerspectiveCorrector.targetSize(for: px, imageSize: Self.imageSize, focalLength35mm: 26)
            #expect(abs(plain.width - focal.width) <= 1 && abs(plain.height - focal.height) <= 1)
        }
    }

    @Test(arguments: [200.0, .nan, 0, -5])
    func implausibleFocalLengthFallsBack(focal: Double) {
        let quad = Self.projectedA4(f35: 26, pitch: 30, offset: (0.02, -0.03))
        let average = Self.averageEdgeSize(quad)
        let size = PerspectiveCorrector.targetSize(for: quad.scaled(to: Self.imageSize), imageSize: Self.imageSize, focalLength35mm: focal)
        #expect(abs(size.width - average.width) <= 2 && abs(size.height - average.height) <= 2, "\(focal): \(size) vs \(average)")
    }
}

extension FixtureTests {
    @Suite struct PerspectiveCorrectorFixtureTests {
        @Test(arguments: Fixtures.names)
        func correctedAspectMatchesSheetOrientation(name: String) throws {
            let fixture = Fixtures.fixture(name)
            let photo = try Fixtures.photo(name)
            let detected = try DocumentDetector().detect(in: photo)
            let page = try PerspectiveCorrector().correct(photo, to: detected.quad)
            print("\(name): photo \(photo.width)x\(photo.height) → page \(page.width)x\(page.height) (\(fixture.orientation))")
            if fixture.isLandscape {
                #expect(page.width > page.height)
            } else {
                #expect(page.height > page.width)
            }
        }

        /// The fixtures are near-frontal photos taken with a 26 mm-equivalent lens: the focal-length correction must agree with
        /// the average edges on them (no regression on ordinary shots).
        @Test(arguments: Fixtures.names)
        func focalLengthAgreesOnNearFrontalPhotos(name: String) throws {
            let url = Fixtures.url(name)
            let focal = ImageCodec().focalLength35mm(of: try Data(contentsOf: url))
            #expect(focal == 26, "\(name): FocalLenIn35mmFilm \(String(describing: focal))")
            let photo = try Fixtures.photo(name)
            let detected = try DocumentDetector().detect(in: photo)
            let imageSize = CGSize(width: photo.width, height: photo.height)
            let px = detected.quad.scaled(to: imageSize)
            let plain = PerspectiveCorrector.targetSize(for: px, imageSize: imageSize, focalLength35mm: nil)
            let corrected = PerspectiveCorrector.targetSize(for: px, imageSize: imageSize, focalLength35mm: focal)
            let ratio = { (s: CGSize) in Double(max(s.width, s.height) / min(s.width, s.height)) }
            let difference = abs(ratio(corrected) - ratio(plain)) / ratio(plain)
            print("\(name): long/short \(ratio(plain)) → \(ratio(corrected)) (\(difference * 100)%)")
            #expect(difference <= 0.03, "\(name): \(difference)")
        }
    }
}

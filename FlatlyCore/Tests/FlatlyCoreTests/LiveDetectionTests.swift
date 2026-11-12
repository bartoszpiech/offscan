import Testing
import Foundation
import CoreGraphics
import CoreVideo
import CoreImage
@testable import FlatlyCore

extension FixtureTests {
    /// `detectLive` on a camera-like pixel buffer must agree with the still-image detector.
    @Suite struct LiveDetectionTests {
        /// Renders `image` into a pixel buffer (BGRA by default; camera-native 420f on request)
        /// rotated back to "sensor" orientation, i.e. the buffer needs `.right` to become upright
        /// again, as for a portrait iPhone's back camera.
        static func sensorBuffer(fromUpright image: CGImage, maxDimension: CGFloat = 1280, pixelFormat: OSType = kCVPixelFormatType_32BGRA) throws -> CVPixelBuffer {
            let ci = CIImage(cgImage: image)
            let scale = maxDimension / CGFloat(max(image.width, image.height))
            // Undo `.right` (90° clockwise) by rotating 90° counter-clockwise.
            let sensor = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale)).oriented(.left)
            let extent = sensor.extent.integral
            let moved = sensor.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            var buffer: CVPixelBuffer?
            let attrs = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
            let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(extent.width), Int(extent.height), pixelFormat, attrs, &buffer)
            try #require(status == kCVReturnSuccess)
            let out = try #require(buffer)
            CIContext().render(moved, to: out)
            return out
        }

        @Test(arguments: Fixtures.sampleNames)
        func liveAgreesWithStillDetection(name: String) throws {
            let photo = try Fixtures.photo(name, maxDimension: 2000)
            let still = try DocumentDetector().detect(in: photo)
            let buffer = try Self.sensorBuffer(fromUpright: photo)
            #expect(CVPixelBufferGetWidth(buffer) > CVPixelBufferGetHeight(buffer) || photo.width > photo.height,
                    "sensor buffer should be landscape for a portrait photo")
            let live = try #require(try DocumentDetector().detectLive(in: buffer, orientation: .right))
            #expect(QuadStabilityTracker.maxCornerDistance(still.quad, live.quad) < 0.04,
                    "live quad \(live.quad) should match still quad \(still.quad)")
        }

        /// The camera delivers YUV 4:2:0 frames; live detection must work on them as on BGRA.
        @Test(arguments: Fixtures.sampleNames)
        func liveDetectsInCameraYUVBuffers(name: String) throws {
            let photo = try Fixtures.photo(name, maxDimension: 2000)
            let still = try DocumentDetector().detect(in: photo)
            let yuv = try Self.sensorBuffer(fromUpright: photo, pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
            #expect(CVPixelBufferGetPixelFormatType(yuv) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
            let live = try #require(try DocumentDetector().detectLive(in: yuv, orientation: .right))
            #expect(QuadStabilityTracker.maxCornerDistance(still.quad, live.quad) < 0.04)
            let bgra = try #require(try DocumentDetector().detectLive(in: try Self.sensorBuffer(fromUpright: photo), orientation: .right))
            #expect(QuadStabilityTracker.maxCornerDistance(bgra.quad, live.quad) < 0.01, "YUV and BGRA frames should give the same outline")
        }
    }
}

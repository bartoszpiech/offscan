import Foundation
import CoreGraphics
import CoreImage

/// The single Core Image context shared by all FlatlyCore services. `CIContext` is thread-safe.
enum CIContextProvider {
    /// Boxes the shared objects: `CIContext`/`CGColorSpace` are thread-safe but only recent SDKs
    /// mark them `Sendable`, so this keeps the code warning-free on every SDK.
    private struct Storage: @unchecked Sendable {
        let context = CIContext(options: [
            .cacheIntermediates: false,
            .useSoftwareRenderer: false,
        ])
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    }
    private static let storage = Storage()

    static var shared: CIContext { storage.context }

    /// sRGB, used as the output colour space whenever the input's colour space is not RGB.
    static var sRGB: CGColorSpace { storage.sRGB }

    /// Renders `image` (cropped to `rect`, default: its extent) into an 8-bit RGBA `CGImage`.
    /// - Parameter colorSpace: output colour space; defaults to sRGB.
    static func render(_ image: CIImage, from rect: CGRect? = nil, colorSpace: CGColorSpace? = nil) throws -> CGImage {
        let bounds = (rect ?? image.extent).integral
        guard !bounds.isInfinite, !bounds.isEmpty,
              let cg = shared.createCGImage(image, from: bounds, format: .RGBA8, colorSpace: colorSpace ?? sRGB)
        else { throw FlatlyCoreError.processingFailed("Core Image render failed") }
        return cg
    }
}

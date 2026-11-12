import Foundation
import CoreGraphics
import PencilKit
// The one sanctioned platform-UI import in FlatlyCore: `PKDrawing.image(from:scale:)` returns a
// UIImage/NSImage, which we immediately convert to CGImage.
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Renders PencilKit drawings and composites them onto pages.
public struct SignatureRenderer: Sendable {
    public init() {}

    /// Renders the drawing into a transparent image of `size` pixels, scaling the drawing's
    /// bounds to fill the target while keeping the aspect ratio (aspect-fit, centred).
    ///
    /// Ink keeps the colour it was drawn in (the app's blue, navy or black): it is rendered in
    /// the light appearance, so it never flips with the device's dark-mode setting. An empty
    /// drawing yields a fully transparent image.
    /// - Throws: `FlatlyCoreError.decodingFailed` when `drawingData` is not a PKDrawing,
    ///   `FlatlyCoreError.processingFailed` when rasterisation fails.
    public func render(drawingData: Data, size: CGSize) throws -> CGImage {
        let width = max(Int(size.width.rounded()), 1)
        let height = max(Int(size.height.rounded()), 1)
        let drawing: PKDrawing
        do {
            drawing = try PKDrawing(data: drawingData)
        } catch {
            throw FlatlyCoreError.decodingFailed
        }
        let context = try Self.makeContext(width: width, height: height)

        let bounds = drawing.bounds
        if !bounds.isNull, !bounds.isEmpty, bounds.width > 0, bounds.height > 0 {
            let scale = min(CGFloat(width) / bounds.width, CGFloat(height) / bounds.height)
            let fitted = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let target = CGRect(
                x: (CGFloat(width) - fitted.width) / 2,
                y: (CGFloat(height) - fitted.height) / 2,
                width: fitted.width,
                height: fitted.height
            )
            let ink = try Self.rasterize(drawing, bounds: bounds, scale: scale, pixelSize: fitted)
            context.interpolationQuality = .high
            context.draw(ink, in: target)
        }

        guard let image = context.makeImage() else {
            throw FlatlyCoreError.processingFailed("Cannot create signature image")
        }
        return image
    }

    /// Draws the signature over `page` inside `placement.frame` (normalised, top-left origin).
    /// The result has the page's pixel size; areas outside the frame are untouched.
    public func composite(_ placement: SignaturePlacement, onto page: CGImage) throws -> CGImage {
        let width = page.width
        let height = page.height
        let context = try Self.makeContext(width: width, height: height)
        let pageRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(page, in: pageRect)

        // Top-left-origin normalised frame → bottom-left-origin pixel rect for CGContext.
        let frame = placement.frame.standardized
        let pixelRect = CGRect(
            x: frame.minX * CGFloat(width),
            y: CGFloat(height) - frame.maxY * CGFloat(height),
            width: frame.width * CGFloat(width),
            height: frame.height * CGFloat(height)
        ).integral

        if pixelRect.width >= 1, pixelRect.height >= 1, pixelRect.intersects(pageRect) {
            let signature = try render(drawingData: placement.drawingData, size: pixelRect.size)
            context.interpolationQuality = .high
            context.draw(signature, in: pixelRect)
        }

        guard let image = context.makeImage() else {
            throw FlatlyCoreError.processingFailed("Cannot composite signature")
        }
        return image
    }

    // MARK: - Helpers

    /// Transparent, premultiplied-alpha sRGB bitmap context.
    private static func makeContext(width: Int, height: Int) throws -> CGContext {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            throw FlatlyCoreError.processingFailed("Cannot create bitmap context \(width)×\(height)")
        }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }

    /// Rasterises `bounds` of the drawing at `scale` pixels per point via PencilKit, in the
    /// light appearance (PencilKit inverts black ink in dark mode).
    private static func rasterize(_ drawing: PKDrawing, bounds: CGRect, scale: CGFloat, pixelSize: CGSize) throws -> CGImage {
        var result: CGImage?
        #if canImport(UIKit)
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            result = drawing.image(from: bounds, scale: scale).cgImage
        }
        #elseif canImport(AppKit)
        let render = {
            let image = drawing.image(from: bounds, scale: scale)
            var proposed = CGRect(origin: .zero, size: pixelSize)
            result = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
        }
        if let aqua = NSAppearance(named: .aqua) {
            aqua.performAsCurrentDrawingAppearance(render)
        } else {
            render()
        }
        #endif
        guard let result else {
            throw FlatlyCoreError.processingFailed("Cannot rasterise signature drawing")
        }
        return result
    }
}

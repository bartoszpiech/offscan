import Foundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// Applies a `ScanFilter` to a page image using Core Image built-in filters only.
///
/// All arithmetic happens in Core Image's default (linear sRGB) working space; outputs are 8-bit
/// RGBA `CGImage`s with the same pixel size as the input.
public struct FilterEngine: Sendable {
    public init() {}

    // MARK: Tuning

    /// `.color`/`.grayscale`: after flattening, this luminance percentile is mapped to white.
    static let whitePercentile: Double = 0.97
    /// Upper bound for that white-point gain (the flattened paper is already ≈ 1).
    static let maximumWhiteGain: Double = 1.5
    /// `.color`/`.grayscale`: S-curve applied in sRGB-encoded space (x → y control points; the
    /// ends are fixed at 0 → 0 and 1 → 1). Darkens ink a little and lifts near-white paper.
    static let toneCurve: [CGPoint] = [
        CGPoint(x: 0.25, y: 0.14),
        CGPoint(x: 0.5, y: 0.42),
        CGPoint(x: 0.75, y: 0.76),
    ]
    /// `.color`: mild saturation boost on top of the S-curve's own (≥ 1, never desaturate).
    static let colorSaturation: Float = 1.05
    /// `.blackAndWhite`: the background is estimated on a copy downsampled to this longest side.
    static let backgroundWorkingSide: CGFloat = 600
    /// `.blackAndWhite`: text removal before blurring (CIMorphologyMaximum radius in working pixels,
    /// ≈ 25 px at full resolution for a 2500 px page).
    static let backgroundMaxFilterRadius: Float = 6
    /// `.blackAndWhite`: Gaussian blur sigma as a fraction of the longest side (≈ side / 40).
    static let backgroundBlurFraction: CGFloat = 1.0 / 40.0
    /// `.blackAndWhite`: contrast boost of the shadow-free page before thresholding.
    static let blackAndWhiteContrast: Float = 1.3
    /// `.blackAndWhite`: CIColorThreshold level in the linear working space (≈ 0.73 in sRGB terms):
    /// pixels darker than half their local paper brightness become black. Tuned on TestFixtures.
    static let blackAndWhiteThreshold: Float = 0.5

    public func apply(_ filter: ScanFilter, to image: CGImage) throws -> CGImage {
        switch filter {
        case .original:
            return image
        case .color:
            return try CIContextProvider.render(color(image), colorSpace: image.rgbOutputColorSpace)
        case .grayscale:
            return try CIContextProvider.render(grayscale(image))
        case .blackAndWhite:
            return try CIContextProvider.render(blackAndWhite(image))
        }
    }

    // MARK: - Pipelines

    /// "Magic colour": illumination flattening (per channel, so colour casts go too), white point,
    /// gentle S-curve, mild saturation boost.
    func color(_ image: CGImage, saturation: Float = Self.colorSaturation) throws -> CIImage {
        let toned = try flattenedAndToned(CIImage(cgImage: image))
        guard saturation != 1 else { return toned }
        let controls = CIFilter.colorControls()
        controls.inputImage = toned
        controls.saturation = saturation
        controls.contrast = 1
        controls.brightness = 0
        return try clamped(output(of: controls, extent: toned.extent))
    }

    /// The `.color` pipeline (without the saturation boost), then luminance.
    func grayscale(_ image: CGImage) throws -> CIImage {
        let toned = try flattenedAndToned(CIImage(cgImage: image))
        let controls = CIFilter.colorControls()
        controls.inputImage = toned
        controls.saturation = 0
        controls.contrast = 1
        controls.brightness = 0
        return try output(of: controls, extent: toned.extent)
    }

    /// Shadow removal + global threshold on the illumination-normalised page.
    func blackAndWhite(
        _ image: CGImage,
        contrast: Float = Self.blackAndWhiteContrast,
        threshold thresholdLevel: Float = Self.blackAndWhiteThreshold,
        maxFilterRadius: Float = Self.backgroundMaxFilterRadius,
        blurFraction: CGFloat = Self.backgroundBlurFraction
    ) throws -> CIImage {
        let input = CIImage(cgImage: image)
        let extent = input.extent

        let toGray = CIFilter.colorControls()
        toGray.inputImage = input
        toGray.saturation = 0
        toGray.contrast = 1
        toGray.brightness = 0
        let gray = try output(of: toGray, extent: extent)

        let background = try estimateBackground(gray, maxFilterRadius: maxFilterRadius, blurFraction: blurFraction)

        // CIDivideBlendMode computes background / input, so the illumination goes in `inputImage`
        // and the page in `inputBackgroundImage` → page / illumination (paper ≈ 1).
        let divide = CIFilter.divideBlendMode()
        divide.inputImage = background
        divide.backgroundImage = gray
        let normalised = try output(of: divide, extent: extent)

        let boost = CIFilter.colorControls()
        boost.inputImage = normalised
        boost.saturation = 0
        boost.contrast = contrast
        boost.brightness = 0
        let boosted = try output(of: boost, extent: extent)

        let threshold = CIFilter.colorThreshold()
        threshold.inputImage = boosted
        threshold.threshold = thresholdLevel
        return try output(of: threshold, extent: extent)
    }

    // MARK: - Helpers

    /// Smooth estimate of the page illumination: downsample, erase dark strokes with a max
    /// filter, blur heavily, upsample back to `gray`'s extent.
    private func estimateBackground(_ gray: CIImage, maxFilterRadius: Float, blurFraction: CGFloat) throws -> CIImage {
        let extent = gray.extent
        let longest = max(extent.width, extent.height)
        let scale = min(1, Self.backgroundWorkingSide / longest)

        var small = gray
        if scale < 1 {
            let lanczos = CIFilter.lanczosScaleTransform()
            lanczos.inputImage = gray
            lanczos.scale = Float(scale)
            lanczos.aspectRatio = 1
            small = try output(of: lanczos, extent: nil)
        }
        let smallExtent = small.extent

        let maxFilter = CIFilter.morphologyMaximum()
        maxFilter.inputImage = small.clampedToExtent()
        maxFilter.radius = maxFilterRadius
        guard let dilated = maxFilter.outputImage else {
            throw FlatlyCoreError.processingFailed("CIMorphologyMaximum failed")
        }

        let sigma = max(smallExtent.width, smallExtent.height) * blurFraction
        let blurred = dilated.clampedToExtent().applyingGaussianBlur(sigma: Double(sigma))

        // Back to full resolution; clamp first so the upscaled edges stay filled.
        let up = blurred.cropped(to: smallExtent).clampedToExtent()
            .transformed(by: CGAffineTransform(scaleX: extent.width / smallExtent.width, y: extent.height / smallExtent.height))
        return up.cropped(to: extent)
    }

    /// Divides the page by its per-channel paper estimate (→ paper ≈ 1 everywhere, no cast),
    /// maps the paper level to white, then applies the S-curve. Result is clamped to [0, 1].
    func flattenedAndToned(_ input: CIImage) throws -> CIImage {
        let extent = input.extent
        let background = try PaperBackgroundEstimator().estimate(input)

        // CIDivideBlendMode computes background / input → page / paper estimate.
        let divide = CIFilter.divideBlendMode()
        divide.inputImage = background
        divide.backgroundImage = input
        let flattened = try output(of: divide, extent: extent)

        // White point: the `whitePercentile` luminance of the flattened page → 1.
        let level = try luminancePercentile(flattened, Self.whitePercentile)
        let gain = CGFloat(min(Self.maximumWhiteGain, max(1, 1 / max(level, 1e-3))))
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = flattened
        matrix.rVector = CIVector(x: gain, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: gain, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: gain, w: 0)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        matrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        let levelled = try clamped(output(of: matrix, extent: extent))

        // S-curve in sRGB-encoded space (perceptually even), then back to linear.
        let encode = CIFilter.linearToSRGBToneCurve()
        encode.inputImage = levelled
        let curve = CIFilter.toneCurve()
        curve.inputImage = try output(of: encode, extent: extent)
        curve.point0 = .zero
        curve.point1 = Self.toneCurve[0]
        curve.point2 = Self.toneCurve[1]
        curve.point3 = Self.toneCurve[2]
        curve.point4 = CGPoint(x: 1, y: 1)
        let decode = CIFilter.sRGBToneCurveToLinear()
        decode.inputImage = try clamped(output(of: curve, extent: extent))
        return try output(of: decode, extent: extent)
    }

    /// Clamps every channel to [0, 1].
    private func clamped(_ image: CIImage) throws -> CIImage {
        let clamp = CIFilter.colorClamp()
        clamp.inputImage = image
        clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
        clamp.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
        return try output(of: clamp, extent: image.extent)
    }

    /// Luminance at percentile `p` (0…1) of a ≤ 256 px copy of `input`.
    private func luminancePercentile(_ input: CIImage, _ p: Double) throws -> Double {
        let extent = input.extent
        let scale = min(1, 256 / max(extent.width, extent.height))
        let small = input
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale), highQualityDownsample: true)
        let w = max(1, Int(small.extent.width.rounded(.down)))
        let h = max(1, Int(small.extent.height.rounded(.down)))
        var pixels = [Float](repeating: 0, count: w * h * 4)
        pixels.withUnsafeMutableBytes { buffer in
            CIContextProvider.shared.render(
                small, toBitmap: buffer.baseAddress!, rowBytes: w * 4 * MemoryLayout<Float>.size,
                bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBAf, colorSpace: nil
            )
        }
        var luminance = [Double](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let r: Float = pixels[i * 4]
            let g: Float = pixels[i * 4 + 1]
            let b: Float = pixels[i * 4 + 2]
            let y: Float = 0.2126 * r + 0.7152 * g + 0.0722 * b
            luminance[i] = Double(y)
        }
        luminance.sort()
        return luminance[min(luminance.count - 1, Int(Double(luminance.count) * p))]
    }

    private func output(of filter: CIFilter, extent: CGRect?) throws -> CIImage {
        guard let image = filter.outputImage else {
            throw FlatlyCoreError.processingFailed("\(filter.name) produced no output")
        }
        if let extent { return image.cropped(to: extent) }
        return image
    }
}

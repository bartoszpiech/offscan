import Foundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// Estimates, for every point of a page photo, the linear RGB colour the *paper* has there
/// (illumination × paper tint). Dividing the page by this estimate flattens uneven lighting and
/// removes colour casts while leaving ink, stamps and pictures alone.
///
/// Pipeline:
/// 1. Downsample to `workingSide` and erase thin dark strokes (text, table lines) with a small
///    `CIMorphologyMaximum` (Core Image).
/// 2. Area-average down to a coarse grid (≈ `gridSide` on the longest side) and read it back.
/// 3. On the CPU, weight every grid cell by how paper-like it is: bright relative to its
///    neighbourhood's upper envelope, not near-black relative to the page's paper white, and
///    neutral relative to the paper's tint. Large dark regions (photos, floor plans, black boxes)
///    and saturated regions (stamps, logos) get weight ≈ 0, so they never darken or tint the
///    estimate — that is what prevents halos and keeps colours.
/// 4. Normalised convolution (box-blur³ ≈ Gaussian) of the weighted grid at a near and a far
///    scale; the far scale and finally the global paper white fill holes with no paper nearby.
/// 5. Upload the grid and upscale it (bilinear) to the input extent.
///
/// Only built-in Core Image filters plus plain Swift on a ~160 px grid; no kernels.
struct PaperBackgroundEstimator: Sendable {
    /// Longest side of the copy the max filter runs on.
    var workingSide: CGFloat = 600
    /// `CIMorphologyMaximum` radius at `workingSide` (≈ 15 px at full size for a 2500 px page).
    /// Kept small: it only needs to erase strokes; large dark areas are handled by the weights.
    var maxFilterRadius: Float = 3.5
    /// Longest side of the grid the weighting and smoothing run on.
    var gridSide: Int = 160
    /// Radius of the local upper envelope (fraction of the grid's longest side).
    var envelopeRadiusFraction: Double = 1.0 / 8.0
    /// A cell darker than this fraction of its local envelope is not paper (soft ramp ±0.1).
    var envelopeRatio: Double = 0.6
    /// A cell darker than this fraction of the global paper white is not paper (soft ramp ±0.03).
    var absoluteRatio: Double = 0.09
    /// Chroma (relative to the paper tint) above which a cell is not paper (soft ramp ±0.08).
    var maximumChroma: Double = 0.25
    /// Smoothing scales (Gaussian sigma as a fraction of the grid's longest side).
    var nearSigmaFraction: Double = 1.0 / 32.0
    var farSigmaFraction: Double = 1.0 / 5.0
    /// The estimate never drops below paper white / `maximumGain` (bounds the brightening).
    var maximumGain: Double = 8

    /// Returns the paper estimate with `image`'s extent (linear working-space RGB, alpha 1).
    func estimate(_ image: CIImage) throws -> CIImage {
        let extent = image.extent
        let longest = max(extent.width, extent.height)
        guard longest >= 1 else { throw FlatlyCoreError.processingFailed("Empty image") }
        let origin = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))

        // 1. Working copy with dark strokes erased.
        var small = origin
        let scale = min(1, workingSide / longest)
        if scale < 1 {
            let lanczos = CIFilter.lanczosScaleTransform()
            lanczos.inputImage = origin
            lanczos.scale = Float(scale)
            lanczos.aspectRatio = 1
            guard let out = lanczos.outputImage else { throw FlatlyCoreError.processingFailed("CILanczosScaleTransform failed") }
            small = out
        }
        let smallExtent = small.extent
        let maxFilter = CIFilter.morphologyMaximum()
        maxFilter.inputImage = small.clampedToExtent()
        maxFilter.radius = maxFilterRadius
        guard let dilated = maxFilter.outputImage?.cropped(to: smallExtent) else {
            throw FlatlyCoreError.processingFailed("CIMorphologyMaximum failed")
        }

        // 2. Coarse grid, exactly covering the page.
        let gw = max(1, Int((extent.width / longest * CGFloat(gridSide)).rounded()))
        let gh = max(1, Int((extent.height / longest * CGFloat(gridSide)).rounded()))
        let gridImage = dilated
            .transformed(by: CGAffineTransform(translationX: -smallExtent.minX, y: -smallExtent.minY))
            .transformed(
                by: CGAffineTransform(scaleX: CGFloat(gw) / smallExtent.width, y: CGFloat(gh) / smallExtent.height),
                highQualityDownsample: true
            )
        var rgba = [Float](repeating: 0, count: gw * gh * 4)
        rgba.withUnsafeMutableBytes { buffer in
            CIContextProvider.shared.render(
                gridImage, toBitmap: buffer.baseAddress!, rowBytes: gw * 4 * MemoryLayout<Float>.size,
                bounds: CGRect(x: 0, y: 0, width: gw, height: gh), format: .RGBAf, colorSpace: nil
            )
        }

        // 3–4. Weighted smoothing on the CPU.
        let background = estimateGrid(rgba, width: gw, height: gh)

        // 5. Back to a CIImage at full size.
        let data = background.withUnsafeBufferPointer { Data(buffer: $0) }
        let grid = CIImage(
            bitmapData: data, bytesPerRow: gw * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: gw, height: gh), format: .RGBAf, colorSpace: nil
        )
        return grid.samplingLinear().clampedToExtent()
            .transformed(by: CGAffineTransform(scaleX: extent.width / CGFloat(gw), y: extent.height / CGFloat(gh)))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .cropped(to: extent)
    }

    // MARK: - Grid maths

    /// `rgba`: linear RGBA floats, row-major. Returns the RGBA background grid (alpha 1).
    func estimateGrid(_ rgba: [Float], width: Int, height: Int) -> [Float] {
        let n = width * height
        var r = [Double](repeating: 0, count: n), g = r, b = r, lum = r
        for i in 0..<n {
            r[i] = Double(max(0, rgba[i * 4]))
            g[i] = Double(max(0, rgba[i * 4 + 1]))
            b[i] = Double(max(0, rgba[i * 4 + 2]))
            lum[i] = 0.2126 * r[i] + 0.7152 * g[i] + 0.0722 * b[i]
        }

        // Global paper white: mean colour of the brightest 10 % of cells.
        let sorted = lum.indices.sorted { lum[$0] > lum[$1] }
        let top = sorted.prefix(max(1, n / 10))
        var white = (r: 0.0, g: 0.0, b: 0.0)
        for i in top { white.r += r[i]; white.g += g[i]; white.b += b[i] }
        let count = Double(top.count)
        white = (max(white.r / count, 1e-3), max(white.g / count, 1e-3), max(white.b / count, 1e-3))
        let whiteLum = max(1e-3, 0.2126 * white.r + 0.7152 * white.g + 0.0722 * white.b)

        // Local upper envelope of luminance.
        let longest = max(width, height)
        let envelopeRadius = max(1, Int((Double(longest) * envelopeRadiusFraction).rounded()))
        let envelope = Self.maxFilter(lum, width: width, height: height, radius: envelopeRadius)

        // Paper-likeness weights.
        var weight = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let relative = lum[i] / max(envelope[i], 1e-6)
            let wEnvelope = Self.ramp(relative, from: envelopeRatio - 0.1, to: envelopeRatio + 0.1)
            let wAbsolute = Self.ramp(lum[i] / whiteLum, from: absoluteRatio - 0.03, to: absoluteRatio + 0.03)
            let nr = r[i] / white.r, ng = g[i] / white.g, nb = b[i] / white.b
            let hi = max(nr, ng, nb), lo = min(nr, ng, nb)
            let chroma = hi > 1e-6 ? (hi - lo) / hi : 0
            let wChroma = 1 - Self.ramp(chroma, from: maximumChroma - 0.08, to: maximumChroma + 0.08)
            weight[i] = wEnvelope * wAbsolute * wChroma
        }

        // Normalised convolution at two scales.
        func smoothed(_ sigmaFraction: Double) -> (r: [Double], g: [Double], b: [Double], w: [Double]) {
            let sigma = max(0.5, Double(longest) * sigmaFraction)
            func blur(_ v: [Double]) -> [Double] { Self.gaussianApprox(v, width: width, height: height, sigma: sigma) }
            var wr = r, wg = g, wb = b
            for i in 0..<n { wr[i] *= weight[i]; wg[i] *= weight[i]; wb[i] *= weight[i] }
            return (blur(wr), blur(wg), blur(wb), blur(weight))
        }
        let near = smoothed(nearSigmaFraction)
        let far = smoothed(farSigmaFraction)
        let farWeight = 0.02, globalWeight = 1e-4

        var out = [Float](repeating: 1, count: n * 4)
        for i in 0..<n {
            let den = near.w[i] + farWeight * far.w[i] + globalWeight
            func channel(_ nearValue: Double, _ farValue: Double, _ globalValue: Double) -> Float {
                let v = (nearValue + farWeight * farValue + globalWeight * globalValue) / den
                return Float(max(v, globalValue / maximumGain, 1e-3))
            }
            out[i * 4] = channel(near.r[i], far.r[i], white.r)
            out[i * 4 + 1] = channel(near.g[i], far.g[i], white.g)
            out[i * 4 + 2] = channel(near.b[i], far.b[i], white.b)
            out[i * 4 + 3] = 1
        }
        return out
    }

    /// 0 below `a`, 1 above `b`, linear in between.
    static func ramp(_ x: Double, from a: Double, to b: Double) -> Double {
        min(1, max(0, (x - a) / (b - a)))
    }

    /// Separable square max filter (window clipped at the borders).
    static func maxFilter(_ v: [Double], width: Int, height: Int, radius: Int) -> [Double] {
        var tmp = v
        for y in 0..<height {
            let row = y * width
            for x in 0..<width {
                var m = -Double.infinity
                for k in max(0, x - radius)...min(width - 1, x + radius) { m = max(m, v[row + k]) }
                tmp[row + x] = m
            }
        }
        var out = tmp
        for x in 0..<width {
            for y in 0..<height {
                var m = -Double.infinity
                for k in max(0, y - radius)...min(height - 1, y + radius) { m = max(m, tmp[k * width + x]) }
                out[y * width + x] = m
            }
        }
        return out
    }

    /// Three box-blur passes per axis (≈ Gaussian of `sigma`), zero padding outside the grid —
    /// correct for normalised convolution, where values and weights are blurred alike.
    static func gaussianApprox(_ v: [Double], width: Int, height: Int, sigma: Double) -> [Double] {
        // Box radius r such that three passes have variance ≈ sigma²: 3·((2r+1)² − 1)/12 = sigma².
        let radius = max(1, Int(((sqrt(4 * sigma * sigma + 1) - 1) / 2).rounded()))
        var data = v
        for _ in 0..<3 {
            data = boxBlur(data, count: width, lines: height, stride: 1, lineStride: width, radius: radius)
            data = boxBlur(data, count: height, lines: width, stride: width, lineStride: 1, radius: radius)
        }
        return data
    }

    /// 1-D box blur (sum / (2r+1), zero padding) along `lines` lines of `count` samples.
    private static func boxBlur(_ v: [Double], count: Int, lines: Int, stride: Int, lineStride: Int, radius: Int) -> [Double] {
        var out = v
        let norm = 1 / Double(2 * radius + 1)
        var prefix = [Double](repeating: 0, count: count + 1)
        for line in 0..<lines {
            let base = line * lineStride
            for i in 0..<count { prefix[i + 1] = prefix[i] + v[base + i * stride] }
            for i in 0..<count {
                let lo = max(0, i - radius), hi = min(count, i + radius + 1)
                out[base + i * stride] = (prefix[hi] - prefix[lo]) * norm
            }
        }
        return out
    }
}

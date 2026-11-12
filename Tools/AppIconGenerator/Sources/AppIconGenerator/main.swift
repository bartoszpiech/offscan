// Offscan app icon generator.
//
// Motif: "a sheet of paper that is switched off". A cream sheet on a poppy-red ground carries a
// navy toggle in its off position (the app never goes online) and two navy text lines.
// Everything is drawn with CoreGraphics in a 1024×1024 design space.
//
// Usage: AppIconGenerator <AppIcon.appiconset directory> [preview.png path]

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Palette

struct RGB {
    var r: CGFloat, g: CGFloat, b: CGFloat

    init(hex: UInt32) {
        r = CGFloat((hex >> 16) & 0xFF) / 255
        g = CGFloat((hex >> 8) & 0xFF) / 255
        b = CGFloat(hex & 0xFF) / 255
    }

    func cg(alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}

/// One appearance of the icon (iOS 18 supports light, dark and tinted app icons).
struct IconStyle {
    var backgroundTop: RGB          // top-left end of the gradient
    var backgroundBottom: RGB       // bottom end of the gradient
    var sheet: RGB
    var toggle: RGB                 // the switch track
    var knob: RGB
    var textLine: RGB
    var shadowAlpha: CGFloat

    /// Poppy ground, cream sheet, navy details.
    static let light = IconStyle(
        backgroundTop: RGB(hex: 0xE14B35),
        backgroundBottom: RGB(hex: 0xCC3A26),
        sheet: RGB(hex: 0xFBF3E4),
        toggle: RGB(hex: 0x1B2748),
        knob: RGB(hex: 0xFBF3E4),
        textLine: RGB(hex: 0x1B2748),
        shadowAlpha: 0.22
    )

    /// Navy ground; the poppy moves to the knob.
    static let dark = IconStyle(
        backgroundTop: RGB(hex: 0x1B2748),
        backgroundBottom: RGB(hex: 0x0C1124),
        sheet: RGB(hex: 0xEFE4D0),
        toggle: RGB(hex: 0x1B2748),
        knob: RGB(hex: 0xE5503B),
        textLine: RGB(hex: 0x1B2748),
        shadowAlpha: 0.45
    )

    /// Tinted icons are supplied as greyscale on black; the system colourises them by luminance.
    static let tinted = IconStyle(
        backgroundTop: RGB(hex: 0x000000),
        backgroundBottom: RGB(hex: 0x000000),
        sheet: RGB(hex: 0xFFFFFF),
        toggle: RGB(hex: 0x2B2B2B),
        knob: RGB(hex: 0xFFFFFF),
        textLine: RGB(hex: 0x555555),
        shadowAlpha: 0.0
    )
}

// MARK: - Geometry (1024 design units, bottom-left origin)

enum Layout {
    static let canvas: CGFloat = 1024

    static let sheet = CGRect(x: 273, y: 170, width: 478, height: 684)
    static let sheetCornerRadius: CGFloat = 60

    /// The switch near the top of the sheet, knob at the left (off).
    static let toggle = CGRect(x: 358, y: 597, width: 308, height: 154)
    static let knobCenter = CGPoint(x: 435, y: 674)
    static let knobRadius: CGFloat = 47

    static let lineHeight: CGFloat = 52
    static let lines = [
        CGRect(x: 358, y: 444, width: 308, height: lineHeight),
        CGRect(x: 358, y: 324, width: 205, height: lineHeight),
    ]
}

// MARK: - Drawing

func drawIcon(in ctx: CGContext, style: IconStyle) {
    let size = Layout.canvas
    let full = CGRect(x: 0, y: 0, width: size, height: size)

    // Background: full-bleed two-stop gradient, a little brighter at the top-left.
    let colors = [style.backgroundTop.cg(), style.backgroundBottom.cg()] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
    ctx.saveGState()
    ctx.addRect(full)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: size * 0.18, y: size),
        end: CGPoint(x: size * 0.62, y: 0),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    ctx.restoreGState()

    // Sheet with a soft drop shadow.
    ctx.saveGState()
    if style.shadowAlpha > 0 {
        ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 54, color: CGColor(gray: 0, alpha: style.shadowAlpha))
    }
    let radius = Layout.sheetCornerRadius
    ctx.addPath(CGPath(roundedRect: Layout.sheet, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(style.sheet.cg())
    ctx.fillPath()
    ctx.restoreGState()

    // The switch, off.
    fillCapsule(Layout.toggle, color: style.toggle.cg(), in: ctx)
    let knob = CGRect(
        x: Layout.knobCenter.x - Layout.knobRadius, y: Layout.knobCenter.y - Layout.knobRadius,
        width: Layout.knobRadius * 2, height: Layout.knobRadius * 2
    )
    ctx.setFillColor(style.knob.cg())
    ctx.fillEllipse(in: knob)

    // Text lines.
    for line in Layout.lines {
        fillCapsule(line, color: style.textLine.cg(), in: ctx)
    }
}

func fillCapsule(_ rect: CGRect, color: CGColor, in ctx: CGContext) {
    let radius = rect.height / 2
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(color)
    ctx.fillPath()
}

// MARK: - Rendering & output

enum GeneratorError: Error, CustomStringConvertible {
    case context, image, write(String)
    var description: String {
        switch self {
        case .context: "Could not create a bitmap context"
        case .image: "Could not create an image from the bitmap context"
        case .write(let path): "Could not write \(path)"
        }
    }
}

/// Renders the icon at `pixels`×`pixels`. App Store icons must be opaque, so the default output
/// has no alpha channel; `maskCornerRadius` (preview only) clips to a rounded square with alpha.
func render(style: IconStyle, pixels: Int, maskCornerRadius: CGFloat? = nil) throws -> CGImage {
    let alphaInfo: CGImageAlphaInfo = maskCornerRadius == nil ? .noneSkipLast : .premultipliedLast
    guard let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: alphaInfo.rawValue
    ) else { throw GeneratorError.context }

    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    let scale = CGFloat(pixels) / Layout.canvas
    ctx.scaleBy(x: scale, y: scale)
    if let radius = maskCornerRadius {
        let rect = CGRect(x: 0, y: 0, width: Layout.canvas, height: Layout.canvas)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.clip()
    }
    drawIcon(in: ctx, style: style)
    guard let image = ctx.makeImage() else { throw GeneratorError.image }
    return image
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw GeneratorError.write(url.path)
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw GeneratorError.write(url.path) }
    print("wrote \(url.path) (\(image.width)×\(image.height))")
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: AppIconGenerator <AppIcon.appiconset dir> [preview.png]\n".utf8))
    exit(64)
}

do {
    let iconSet = URL(fileURLWithPath: arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
    try writePNG(render(style: .light, pixels: 1024), to: iconSet.appendingPathComponent("icon-1024.png"))
    try writePNG(render(style: .dark, pixels: 1024), to: iconSet.appendingPathComponent("icon-1024-dark.png"))
    try writePNG(render(style: .tinted, pixels: 1024), to: iconSet.appendingPathComponent("icon-1024-tinted.png"))

    if arguments.count >= 3 {
        // iOS-like continuous corner approximation: radius ≈ 22.4 % of the side.
        let preview = try render(style: .light, pixels: 180, maskCornerRadius: Layout.canvas * 0.224)
        try writePNG(preview, to: URL(fileURLWithPath: arguments[2]))
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}

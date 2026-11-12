import Foundation
import CoreGraphics
import CoreText

/// Builds a searchable PDF: each page is the rendered image with an invisible text layer on top.
public struct PDFExporter: Sendable {
    public init() {}

    /// Width of `fitToContent` pages (A4 width in points).
    static let fitToContentWidth: CGFloat = 595.276

    /// Whether `password` can protect a PDF: non-empty and printable ASCII only (U+0020…U+007E,
    /// i.e. letters without accents, digits, space and symbols). CoreGraphics' PDF security
    /// handler accepts only ASCII passwords, and anything else makes the PDF context fail.
    public static func isSupportedPassword(_ password: String) -> Bool {
        !password.isEmpty && password.unicodeScalars.allSatisfy { (0x20...0x7E).contains($0.value) }
    }

    /// One PDF page per `ExportPage`.
    ///
    /// - The image is re-encoded as JPEG at `compression.jpegQuality` and embedded as-is
    ///   (DCTDecode), aspect-fit and centred in the page box without margins.
    /// - `a4`/`letter` pages turn landscape for landscape images; `fitToContent` pages are
    ///   595.276 pt wide with the image's aspect ratio.
    /// - OCR lines are drawn as invisible text (render mode 3) stretched over their bounding
    ///   boxes so the PDF is searchable and selection highlights the right area. Each line is
    ///   laid along its text direction (`OCRLine.direction`), so sideways and upside-down text
    ///   selects, highlights and copies correctly too.
    /// - Metadata: Title = `title`, Creator = "Offscan".
    /// - Encrypted (AES-128) when `password` is given; owner and user password are the same, so
    ///   the password grants full access. `nil` leaves the PDF unencrypted.
    ///
    /// Downsampling to `compression.maxPixelDimension` is the caller's job. Every page's image is
    /// alive for the whole call; for long documents prefer `writePDF(to:pageCount:…)`.
    /// - Throws: `FlatlyCoreError.processingFailed` for an empty page list, a `password` that
    ///   `isSupportedPassword` rejects, or if the PDF context cannot be created;
    ///   `FlatlyCoreError.encodingFailed` if an image cannot be encoded.
    public func makePDF(
        pages: [ExportPage],
        pageSize: PageSizeOption,
        compression: CompressionLevel,
        title: String,
        password: String? = nil
    ) throws -> Data {
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output) else {
            throw FlatlyCoreError.processingFailed("Cannot create PDF data consumer")
        }
        try render(
            into: consumer, pageCount: pages.count, pageSize: pageSize, compression: compression,
            title: title, password: password
        ) { pages[$0] }
        return output as Data
    }

    /// Streams the same PDF as `makePDF` into the file at `url`, one page at a time:
    /// `page(index)` is called for `0..<pageCount` in order, and each page's image is released
    /// before the next one is requested, so memory stays flat however long the document is.
    /// Encrypted (AES-128) when `password` is given; owner and user password are the same, so the
    /// password grants full access.
    ///
    /// - Throws: whatever `page` throws (e.g. `CancellationError`), plus the `makePDF` errors and
    ///   `FlatlyCoreError.io` if the file cannot be created. An unsupported `password` throws
    ///   before the file is created. On any later error the file may be left partially written;
    ///   deleting it is the caller's job.
    public func writePDF(
        to url: URL,
        pageCount: Int,
        pageSize: PageSizeOption,
        compression: CompressionLevel,
        title: String,
        password: String? = nil,
        page: (Int) throws -> ExportPage
    ) throws {
        // Before the consumer exists, so a rejected password leaves no empty file behind.
        try Self.validate(password: password)
        guard let consumer = CGDataConsumer(url: url as CFURL) else {
            throw FlatlyCoreError.io("Cannot create PDF file at \(url.path)")
        }
        try render(
            into: consumer, pageCount: pageCount, pageSize: pageSize, compression: compression,
            title: title, password: password, page: page
        )
    }

    /// Throws `FlatlyCoreError.processingFailed` when `password` is given but not supported.
    private static func validate(password: String?) throws {
        if let password, !isSupportedPassword(password) {
            throw FlatlyCoreError.processingFailed("Unsupported PDF password")
        }
    }

    private func render(
        into consumer: CGDataConsumer,
        pageCount: Int,
        pageSize: PageSizeOption,
        compression: CompressionLevel,
        title: String,
        password: String?,
        page: (Int) throws -> ExportPage
    ) throws {
        guard pageCount > 0 else {
            throw FlatlyCoreError.processingFailed("PDF export needs at least one page")
        }
        try Self.validate(password: password)
        var info: [CFString: Any] = [
            kCGPDFContextTitle: title,
            kCGPDFContextCreator: "Offscan"
        ]
        if let password {
            // Same owner and user password: whoever opens the file has full access. A 128-bit
            // key makes CoreGraphics write AES-128 (V4/R4) rather than RC4.
            info[kCGPDFContextOwnerPassword] = password
            info[kCGPDFContextUserPassword] = password
            info[kCGPDFContextEncryptionKeyLength] = 128
        }
        var defaultBox = CGRect(origin: .zero, size: pageSize.portraitPointSize ?? CGSize(width: 595.276, height: 841.89))
        guard let context = CGContext(consumer: consumer, mediaBox: &defaultBox, info as CFDictionary) else {
            throw FlatlyCoreError.processingFailed("Cannot create PDF context")
        }
        defer { context.closePDF() }

        for index in 0..<pageCount {
            // The pool drains the page's decoded bitmap (and ImageIO's autoreleased objects)
            // before the next page is loaded.
            try autoreleasepool {
                let page = try page(index)
                let imageSize = CGSize(width: page.image.width, height: page.image.height)
                let mediaBox = Self.pageBox(for: imageSize, pageSize: pageSize)
                let imageRect = Self.aspectFitRect(for: imageSize, in: mediaBox)

                let embedded = try Self.jpegBackedImage(page.image, quality: compression.jpegQuality)

                var box = mediaBox
                let boxData = Data(bytes: &box, count: MemoryLayout<CGRect>.size) as CFData
                context.beginPDFPage([kCGPDFContextMediaBox: boxData] as CFDictionary)
                context.interpolationQuality = .high
                context.draw(embedded, in: imageRect)
                if let ocr = page.ocr {
                    Self.drawInvisibleText(ocr, in: imageRect, context: context)
                }
                context.endPDFPage()
            }
        }
    }

    // MARK: - Geometry

    /// Page box in points for an image of `imageSize` pixels.
    static func pageBox(for imageSize: CGSize, pageSize: PageSizeOption) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: pageSize.portraitPointSize ?? CGSize(width: fitToContentWidth, height: 841.89))
        }
        if let portrait = pageSize.portraitPointSize {
            let landscape = imageSize.width > imageSize.height
            let size = landscape ? CGSize(width: portrait.height, height: portrait.width) : portrait
            return CGRect(origin: .zero, size: size)
        }
        let width = fitToContentWidth
        return CGRect(x: 0, y: 0, width: width, height: width * imageSize.height / imageSize.width)
    }

    /// Largest rect with the image's aspect ratio that fits in `bounds`, centred.
    static func aspectFitRect(for imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    // MARK: - Image

    /// Re-encodes `image` as JPEG and wraps the JPEG bytes in a `CGImage` so the PDF context
    /// embeds the compressed stream directly (DCTDecode) instead of re-compressing pixels.
    private static func jpegBackedImage(_ image: CGImage, quality: CGFloat) throws -> CGImage {
        let jpeg = try JPEGEncoding.encode(image, quality: quality)
        guard let provider = CGDataProvider(data: jpeg as CFData),
              let decoded = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else {
            throw FlatlyCoreError.encodingFailed
        }
        return decoded
    }

    // MARK: - Text layer

    /// Draws each OCR line as invisible Helvetica text stretched to cover its bounding box.
    /// Sideways and upside-down lines (`OCRLine.direction`) are rotated about the box centre and
    /// laid along its long side, with the font size taken from the side across the text.
    private static func drawInvisibleText(_ ocr: OCRResult, in imageRect: CGRect, context: CGContext) {
        let unitFont = CTFontCreateWithName("Helvetica" as CFString, 1, nil)
        let unitHeight = max(CTFontGetAscent(unitFont) + CTFontGetDescent(unitFont), 0.5)
        let unitDescent = CTFontGetDescent(unitFont)

        context.saveGState()
        context.setTextDrawingMode(.invisible)
        defer { context.restoreGState() }

        for line in ocr.lines {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let box = line.boundingBox.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            guard !box.isNull, box.width > 0, box.height > 0 else { continue }

            // PDF space is bottom-left origin like the normalised box, so y maps directly.
            let rect = CGRect(
                x: imageRect.minX + box.minX * imageRect.width,
                y: imageRect.minY + box.minY * imageRect.height,
                width: box.width * imageRect.width,
                height: box.height * imageRect.height
            )

            // `along` runs with the text, `across` from descender to ascender.
            let direction = line.direction ?? .none
            let along = direction.swapsDimensions ? rect.height : rect.width
            let across = direction.swapsDimensions ? rect.width : rect.height

            let fontSize = across / unitHeight
            let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
            let attributed = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font
            ])
            let ctLine = CTLineCreateWithAttributedString(attributed)
            let naturalWidth = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
            guard naturalWidth > 0 else { continue }

            // Stretch along the text so the invisible text spans exactly the box (selection and
            // search highlights then match the visible words). The scale goes into the CTM
            // rather than the text matrix: with a scaled text matrix CoreGraphics compensates
            // glyph positions with character spacing, and lines that mix font subsets (e.g.
            // "Łódź", where Ł/ź live in a second subset) get extracted with spurious spaces.
            context.saveGState()
            if direction == .none {
                context.translateBy(x: rect.minX, y: rect.minY + unitDescent * fontSize)
            } else {
                // PDF space is y-up, so CG's positive angle is counter-clockwise and a clockwise
                // quarter turn is negative. After the rotation the text runs along +x from the
                // box's start edge (top for `.quarter`, right for `.half`, bottom for
                // `.threeQuarters`).
                context.translateBy(x: rect.midX, y: rect.midY)
                context.rotate(by: -CGFloat(direction.radians))
                context.translateBy(x: -along / 2, y: -across / 2 + unitDescent * fontSize)
            }
            context.scaleBy(x: along / naturalWidth, y: 1)
            context.textMatrix = .identity
            context.textPosition = .zero
            CTLineDraw(ctLine, context)
            context.restoreGState()
        }
    }
}

import Foundation
import CoreGraphics
import ImageIO

/// Decoding (HEIC/JPEG/PNG, EXIF orientation applied) and encoding (JPEG/PNG) via ImageIO.
public struct ImageCodec: Sendable {
    public init() {}

    /// Decodes image data, applying EXIF orientation so the returned `CGImage` is upright.
    /// - Parameters:
    ///   - index: image index inside the file (a page of a multi-page TIFF); 0 for ordinary photos.
    ///     Throws `FlatlyCoreError.decodingFailed` when out of range.
    ///   - maxDimension: when set, downsamples during decode (memory friendly).
    public func decode(_ data: Data, index: Int = 0, maxDimension: Int? = nil) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw FlatlyCoreError.decodingFailed
        }
        return try decode(source: source, index: index, maxDimension: maxDimension)
    }

    /// Decodes the image file at `url` (see `decode(_:index:maxDimension:)`).
    public func decode(contentsOf url: URL, index: Int = 0, maxDimension: Int? = nil) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw FlatlyCoreError.decodingFailed
        }
        return try decode(source: source, index: index, maxDimension: maxDimension)
    }

    /// Number of pages to import from an image file: the frame count of a multi-page TIFF, 1 for
    /// any other decodable image (HEIC bursts/sequences, animated GIF/PNG count as one page), 0
    /// when the data isn't a readable image.
    public func pageCount(_ data: Data) -> Int {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return 0 }
        return pageCount(source: source)
    }

    /// Like `pageCount(_:)`, reading only what's needed from the file at `url`.
    public func pageCount(contentsOf url: URL) -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return 0 }
        return pageCount(source: source)
    }

    /// Encodes `image` as JPEG.
    /// - Parameter focalLength35mm: when set (finite, > 0), written as EXIF `FocalLenIn35mmFilm` so a
    ///   stored camera photo keeps what `PerspectiveCorrector` needs. No other metadata is written:
    ///   no GPS, no orientation, no maker notes.
    public func jpegData(_ image: CGImage, quality: CGFloat, focalLength35mm: Double? = nil) throws -> Data {
        var properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: min(max(quality, 0), 1)
        ]
        if let focalLength35mm, focalLength35mm.isFinite, focalLength35mm > 0 {
            properties[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifFocalLenIn35mmFilm: Int(focalLength35mm.rounded())]
        }
        return try encode(image, type: "public.jpeg", properties: properties)
    }

    /// The 35 mm-equivalent focal length stored in the image's EXIF (`FocalLenIn35mmFilm`), or nil.
    /// Only reported for a 4:3 frame (within 1 %): the value describes an uncropped camera frame,
    /// and for crops or other formats it would be wrong.
    public func focalLength35mm(of data: Data) -> Double? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        guard let value = (exif?[kCGImagePropertyExifFocalLenIn35mmFilm] as? NSNumber)?.doubleValue,
              value.isFinite, value > 0 else { return nil }
        let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        guard min(width, height) > 0, abs(max(width, height) / min(width, height) - 4.0 / 3.0) <= 4.0 / 3.0 * 0.01 else { return nil }
        return value
    }

    public func pngData(_ image: CGImage) throws -> Data {
        try encode(image, type: "public.png", properties: [:])
    }

    // MARK: - Private

    private func pageCount(source: CGImageSource) -> Int {
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return 0 }
        // Exact type match: DNG / camera RAW (TIFF-based) never splits into pages.
        return (CGImageSourceGetType(source) as String?) == "public.tiff" ? count : 1
    }

    private func decode(source: CGImageSource, index: Int, maxDimension: Int?) throws -> CGImage {
        guard index >= 0, index < CGImageSourceGetCount(source) else { throw FlatlyCoreError.decodingFailed }
        let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
        let pixelWidth = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let pixelHeight = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0

        if let maxDimension, maxDimension > 0, max(pixelWidth, pixelHeight) > maxDimension || pixelWidth == 0 {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
                throw FlatlyCoreError.decodingFailed
            }
            return image
        }

        let options: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateImageAtIndex(source, index, options as CFDictionary) else {
            throw FlatlyCoreError.decodingFailed
        }
        let rawOrientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up
        return try image.applyingOrientation(orientation)
    }

    private func encode(_ image: CGImage, type: String, properties: [CFString: Any]) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, type as CFString, 1, nil) else {
            throw FlatlyCoreError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FlatlyCoreError.encodingFailed }
        return data as Data
    }
}

# Offscan architecture

Offscan = **FlatlyCore** (logic, cross-platform Swift package) + **FlatlyApp** (SwiftUI iOS app).
Everything runs on-device. There is no network layer.

```
flatly/
├── project.yml                 XcodeGen spec (app + UI tests; FlatlyCore as local package)
├── FlatlyCore/                 Swift package, platforms iOS 17 / macOS 14, Swift 6
│   ├── Sources/FlatlyCore/
│   │   ├── Imaging/            CGImage loading, Quadrilateral, DocumentDetector, QuadStabilityTracker,
│   │   │                       PerspectiveCorrector, ScanFilter/FilterEngine, ImageTransforms,
│   │   │                       PageRenderer, ThumbnailGenerator, ImageCodec, PDFPageRasterizer
│   │   ├── OCR/                TextRecognizer, OCRResult/OCRLine, OCRResult.readableText
│   │   ├── Export/             PDFExporter, JPEGExporter, PageSizeOption, CompressionLevel
│   │   ├── Library/            DocumentNaming, SearchMatcher (+ firstMatch → SearchMatch), SortOption,
│   │   │                       OrderedSelection, DeletionRetention
│   │   ├── Storage/            PageImageStore (files on disk per page UUID)
│   │   └── Signature/          SignatureRenderer, SignaturePlacement, SignatureSpotFinder
│   └── Tests/FlatlyCoreTests/  Swift Testing; fixtures resolved relative to #filePath
├── FlatlyApp/
│   ├── App/                    FlatlyApp (entry), RootView, AppServices, StartupErrorView,
│   │   │                       AppDelegate + SceneDelegate + QuickActionInbox (Home Screen quick action),
│   │   │                       Color.onAccent / .onAccentForeground() (labels on accent backgrounds),
│   │   │                       AppRouter + FolderRoute + RecentlyDeletedRoute (navigation values)
│   │   └── Demo/               DEBUG only: demo library for screenshots (FLATLY_DEMO_DATA=1),
│   │                           DemoCameraFeed (desk-photo stand-in for the camera in the simulator)
│   ├── Persistence/            SwiftData @Model classes + DocumentStore (ONLY place SwiftData is used)
│   ├── Features/
│   │   ├── Library/            LibraryView (folders, Recent strip, search, Select mode), DocumentCard,
│   │   │                       SearchResultRow, SelectionBarLabel, MoveToFolderSheet, FolderRow,
│   │   │                       LibraryFolderRowLabel, RecentlyDeletedFolderRow, RecentlyDeletedView,
│   │   │                       RecentlyDeletedRow
│   │   ├── Camera/             Offscan's camera: CameraController + CaptureSessionPipeline (AVFoundation),
│   │   │                       CameraPreviewView, LiveQuadOverlay, DocumentCameraScreen, CameraPageQueue,
│   │   │                       CapturedPagesSheet, CameraCaptureFlow
│   │   ├── Scan/               ScanCaptureSheet (switch: Offscan camera / Apple scanner), VisionKitCaptureFlow,
│   │   │                       DocumentCameraView (VisionKit wrapper)
│   │   ├── Import/             ImportFlowView (PhotosPicker + fileImporter), FileImportSelection (PDF / TIFF
│   │   │                       pages), StagedPageReview (shared corner review)
│   │   ├── CornerAdjust/       CornerAdjustView + MagnifierLoupe
│   │   ├── Editor/             DocumentDetailView, PageGridView, PageEditorView (filter/rotate/crop/signature entry)
│   │   ├── OCRText/            OCRTextView, ReadableTextCache (readable text: copy / share, re-run recognition)
│   │   ├── Export/             ExportSheet (PDF/JPG, page size, compression, PDF password, share, save to Files),
│   │   │                       PDFPasswordView, QuickPDFShareModifier (one-tap Share PDF, also for several documents)
│   │   ├── Signature/          SignatureCanvasView (PencilKit), SignatureInk, SignaturePlacementView
│   │   ├── Settings/           SettingsView (privacy, Face ID / passcode lock, default filter, Advanced: camera choice +
│   │   │                       edge review, about)
│   │   └── Lock/               AppLockManager, LockWindowPresenter, LockScreenView
│   ├── Services/               ScanProcessor (background actor driving FlatlyCore for the app),
│   │                           DocumentAssembler, LibrarySearch, ImageCache,
│   │                           FlatlyCoreError+LocalizedError (user-facing core error messages)
│   └── Resources/              Assets.xcassets (AppIcon), Localizable.xcstrings, InfoPlist.xcstrings,
│                               PrivacyInfo.xcprivacy (privacy manifest)
├── FlatlyUITests/
├── Tools/
│   ├── AppIconGenerator/       Swift package executable: renders icon PNG with CoreGraphics
│   └── Typecheck/              PersistenceStubs.swift (stand-in for Persistence/ during Catalyst type-check)
├── TestFixtures/               photos/*.heic (synthetic) + expected.json; private/ is local only
└── scripts/
```

## 1. FlatlyCore public API (contract)

All services are `public struct X: Sendable` with `public init()` and synchronous throwing
methods unless stated. Images cross the API as `CGImage` (already orientation-normalised,
i.e. EXIF orientation applied). Coordinates that are "normalised" are in the unit square
with **origin at the bottom-left** (Vision convention) unless stated.

### Imaging
```swift
public struct Quadrilateral: Sendable, Hashable, Codable {
    public var topLeft, topRight, bottomRight, bottomLeft: CGPoint   // normalised, bottom-left origin
    public init(topLeft:topRight:bottomRight:bottomLeft:)
    public static let fullFrame: Quadrilateral
    public static let minimumTurn: CGFloat                            // 1e-4: smaller corner turns count as collinear
    public static let minimumEdgeLength: CGFloat                      // 0.01: shorter edges mean coincident corners
    /// Strictly clockwise turn at every corner (TL → TR → BR → BL, bottom-left origin) and no edge
    /// shorter than `minimumEdgeLength`. Rejects bow-ties, reflex corners, mirrored (counter-clockwise)
    /// outlines, collinear or coincident corners and NaN. The corner editor, the detector and
    /// `PerspectiveCorrector` all use it.
    public var isConvex: Bool
    public var area: CGFloat                                          // unsigned normalised area (0...1)
    public func scaled(to size: CGSize) -> Quadrilateral              // → pixel coords, still bottom-left origin
    public func flippedVertically() -> Quadrilateral                  // bottom-left ↔ top-left origin
    public static func ordered(from points: [CGPoint]) -> Quadrilateral?  // sorts 4 arbitrary points
}

public struct DetectedDocument: Sendable {
    public var quad: Quadrilateral
    public var confidence: Float            // 0...1
    public enum Source: Sendable { case segmentation, rectangles, fullFrame }
    public var source: Source
}

public struct DocumentDetector: Sendable {
    public init()
    /// VNDetectDocumentSegmentationRequest → VNDetectRectanglesRequest → fullFrame fallback.
    public func detect(in image: CGImage) throws -> DetectedDocument
    /// Live camera frames: segmentation only, nil when nothing confident. `orientation` rotates the
    /// sensor-oriented buffer upright (`.right` for portrait + back camera); the quad is in that upright frame.
    public func detectLive(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) throws -> DetectedDocument?
}

/// Auto-capture: feed live detections; smooths the quad and reports steadiness.
public struct QuadStabilityTracker: Sendable {
    public init(tolerance: CGFloat = 0.02, requiredDuration: TimeInterval = 0.9, minimumArea: CGFloat = 0.15, dropoutGrace: TimeInterval = 0.35)
    public private(set) var smoothedQuad: Quadrilateral?
    public func progress(at now: Date) -> Double          // 0...1 of the steady period; 0 below minimumArea, holds during dropouts
    /// Steady for `requiredDuration`, at least `minimumArea`, and the latest frame had a sheet
    /// (a dropout keeps the outline and the steady period but never fires).
    public func isStable(at now: Date) -> Bool
    public var isSheetTooSmall: Bool                      // tracked sheet < minimumArea ("Move closer" hint)
    public mutating func update(with quad: Quadrilateral?, at now: Date)
    public mutating func reset()                          // after each capture
}

public struct PerspectiveCorrector: Sendable {
    public init()
    /// Crops `image` to `quad` (normalised, bottom-left origin) and warps it to a flat rectangle.
    /// Without `focalLength35mm` the output size is the quad's average edge lengths in pixels. With
    /// the 35 mm-equivalent focal length of the uncropped camera frame (EXIF `FocalLenIn35mmFilm`)
    /// the aspect ratio follows the real sheet (Zhang–He rectangle recovery), keeping the longer
    /// measured side; implausible values (outside 8…400 mm, > 25 % correction) fall back.
    /// Throws `FlatlyCoreError.invalidQuadrilateral` unless `quad.isConvex`.
    public func correct(_ image: CGImage, to quad: Quadrilateral, focalLength35mm: Double? = nil) throws -> CGImage
}

public enum ScanFilter: String, CaseIterable, Sendable, Codable {
    case original, color, grayscale, blackAndWhite
}

public struct FilterEngine: Sendable {
    public init()
    /// `.original` returns the input unchanged. `.color` = paper-background estimate → per-channel
    /// divide (flattens shadows and colour cast) → white point → S-curve; colours preserved.
    /// `.grayscale` = same, then luminance. `.blackAndWhite` = shadow removal (divide by blurred
    /// background) + adaptive threshold → crisp bi-level-looking text.
    public func apply(_ filter: ScanFilter, to image: CGImage) throws -> CGImage
}

public enum Rotation: Int, Sendable, Codable, CaseIterable {   // quarter turns clockwise
    case none = 0, quarter = 1, half = 2, threeQuarters = 3
    public func rotatedClockwise() -> Rotation
    public func rotatedCounterClockwise() -> Rotation
}

public struct ImageTransforms: Sendable {
    public init()
    public func rotate(_ image: CGImage, by rotation: Rotation) throws -> CGImage
    /// `rect` is normalised with **top-left** origin (UI convention).
    public func crop(_ image: CGImage, to rect: CGRect) throws -> CGImage
    public func resized(_ image: CGImage, maxDimension: Int) throws -> CGImage
}

/// Everything needed to turn a page's stored original into its displayed/exported image.
public struct PageRenderRecipe: Sendable, Hashable, Codable {
    public var cropRect: CGRect?            // normalised, top-left origin, nil = no crop
    public var filter: ScanFilter
    public var rotation: Rotation
    public var signature: SignaturePlacement?
    public init(cropRect: CGRect? = nil, filter: ScanFilter = .color, rotation: Rotation = .none, signature: SignaturePlacement? = nil)
}

public struct PageRenderer: Sendable {
    public init()
    /// original → crop → filter → rotate → composite signature.
    public func render(_ original: CGImage, recipe: PageRenderRecipe) throws -> CGImage
}

public struct ThumbnailGenerator: Sendable {
    public init()
    public func thumbnail(for image: CGImage, maxDimension: Int = 400) throws -> CGImage
}

public struct ImageCodec: Sendable {
    public init()
    /// Loads from HEIC/JPEG/PNG/TIFF data, applying EXIF orientation. Optionally downsamples.
    /// `index` picks a page of a multi-page TIFF (0 for photos; out of range → `.decodingFailed`).
    public func decode(_ data: Data, index: Int = 0, maxDimension: Int? = nil) throws -> CGImage
    public func decode(contentsOf url: URL, index: Int = 0, maxDimension: Int? = nil) throws -> CGImage
    /// Pages to import: frame count of a `public.tiff` (DNG/RAW never split), 1 for any other
    /// decodable image (HEIC sequences, animated GIF/PNG), 0 when unreadable.
    public func pageCount(_ data: Data) -> Int
    public func pageCount(contentsOf url: URL) -> Int
    /// `focalLength35mm` (finite, > 0) is written as the only EXIF tag (`FocalLenIn35mmFilm`);
    /// no GPS, orientation or maker notes are ever written.
    public func jpegData(_ image: CGImage, quality: CGFloat, focalLength35mm: Double? = nil) throws -> Data
    /// EXIF `FocalLenIn35mmFilm`, reported only for a 4:3 frame (within 1 %), else nil.
    public func focalLength35mm(of data: Data) -> Double?
    public func pngData(_ image: CGImage) throws -> Data
}

/// Renders pages of an existing PDF (CoreGraphics only) so a PDF can be imported as scan pages:
/// crop box, `/Rotate` applied (upright), on opaque white, sRGB. Password-protected PDFs are
/// refused; owner-password-only PDFs (print/copy restrictions) open.
public struct PDFPageRasterizer: Sendable {
    public init()
    public func pageCount(of url: URL) throws -> Int        // .unreadable / .passwordProtected
    /// Longer side = `maxDimension` (small pages are scaled up). `.pageOutOfRange` for a bad index.
    public func render(pageAt index: Int, of url: URL, maxDimension: Int = 3500) throws -> CGImage
}
public enum PDFPageRasterizerError: Error, Sendable, Equatable {
    case unreadable, passwordProtected, pageOutOfRange, renderFailed
}
```

### OCR
```swift
public struct OCRLine: Sendable, Hashable, Codable {
    public var text: String
    public var boundingBox: CGRect          // normalised, bottom-left origin (Vision), axis-aligned
    public var confidence: Float
    /// Which way the text runs, in quarter turns clockwise from upright left-to-right text
    /// (`.quarter` reads top to bottom, `.half` upside down, `.threeQuarters` bottom to top).
    /// nil = unknown (OCR stored before this field existed); treat as `.none`.
    public var direction: Rotation?
    public init(text: String, boundingBox: CGRect, confidence: Float, direction: Rotation? = nil)
}
public struct OCRResult: Sendable, Hashable, Codable {
    public var lines: [OCRLine]
    /// One line per observation. Used for search and the PDF text layer.
    public var text: String { lines.map(\.text).joined(separator: "\n") }
    /// For reading, copying and sharing (OCRTextView): lines split only because a paragraph
    /// wrapped are joined with a space, a line-end hyphen before a lowercase continuation is
    /// removed, other line breaks are kept and a visible blank gap becomes an empty line.
    public var readableText: String
    public static let empty: OCRResult
}
public struct TextRecognizer: Sendable {
    public init()
    /// VNRecognizeTextRequest, `.accurate`, languages ["pl-PL","en-US"], automatic language
    /// detection on, language correction on. Each line gets its `direction` from the
    /// observation's top edge (measured in pixel space), so sideways and upside-down text is kept.
    public func recognize(_ image: CGImage) throws -> OCRResult
}
```

### Export
```swift
public enum PageSizeOption: String, CaseIterable, Sendable, Codable {
    case a4, letter, fitToContent
    /// `.letter` in US-Letter regions (CLDR: US, CA, MX, PH, …), otherwise `.a4`; nil/unknown → `.a4`.
    public static func defaultSize(forRegion regionCode: String?) -> PageSizeOption
    public static var regionDefault: PageSizeOption       // for Locale.current; default `exportPageSize`
}
public enum CompressionLevel: String, CaseIterable, Sendable, Codable {
    case low, medium, high      // low = best quality / biggest file
    public var jpegQuality: CGFloat     // 0.9 / 0.7 / 0.5
    public var maxPixelDimension: Int   // 3000 / 2200 / 1600
}
public struct ExportPage: Sendable {
    public var image: CGImage
    public var ocr: OCRResult?          // text layer source; coordinates relative to `image`
    public init(image: CGImage, ocr: OCRResult?)
}
public struct PDFExporter: Sendable {
    public init()
    /// One PDF page per ExportPage. Image is drawn to fill the page box keeping aspect ratio;
    /// for a4/letter the page is rotated to landscape when the image is landscape. The OCR
    /// lines are drawn as **invisible** text (text render mode 3 / `.invisible`) positioned on
    /// their bounding boxes so the PDF is searchable/selectable; each line is laid along its
    /// `OCRLine.direction`, so sideways and upside-down text selects and copies correctly.
    /// Metadata: Title, Creator "Offscan". With a `password` the PDF is encrypted (AES-128, V4/R4),
    /// owner and user password the same (the password grants full access); nil = unencrypted.
    /// An unsupported password throws `.processingFailed` (before `writePDF` creates its file).
    public func makePDF(pages: [ExportPage], pageSize: PageSizeOption, compression: CompressionLevel, title: String,
                        password: String? = nil) throws -> Data
    /// Same PDF, streamed to `url`: `page(i)` is called for 0..<pageCount in order and each page is
    /// released before the next, so memory stays flat. The app's export uses this one.
    public func writePDF(to url: URL, pageCount: Int, pageSize: PageSizeOption, compression: CompressionLevel,
                         title: String, password: String? = nil, page: (Int) throws -> ExportPage) throws
    /// Non-empty printable ASCII (U+0020…U+007E) only: CoreGraphics' PDF security handler takes
    /// nothing else, and any other password makes the PDF context fail.
    public static func isSupportedPassword(_ password: String) -> Bool
}
public struct JPEGExporter: Sendable {
    public init()
    public func makeJPEG(_ image: CGImage, compression: CompressionLevel) throws -> Data
}
```

### Library logic
```swift
public struct DocumentNaming: Sendable {
    /// e.g. prefix "Scan" → "Scan 2026-10-08 14.32"
    public static func defaultTitle(prefix: String, date: Date, calendar: Calendar = .current) -> String
    public static func uniqueTitle(_ title: String, existing: Set<String>) -> String   // "Title (2)"
    /// Export file name: no `/` `:` or control characters, no leading dot, ≤ 255 UTF-8 bytes in total
    /// (title shortened, suffix and extension kept). ("Faktura", " 2", "jpg") → "Faktura 2.jpg"
    public static func fileName(for title: String, suffix: String = "", pathExtension: String, fallback: String = "Offscan") -> String
}
public struct SearchMatcher: Sendable {
    public init()
    public func normalize(_ s: String) -> String                       // lowercased, diacritics folded
    public func matches(query: String, title: String, content: String) -> Bool   // all query tokens found
    public func score(query: String, title: String, content: String) -> Int      // higher = better
    /// Normalise once, score many times (normalising is the expensive part):
    public struct PreparedQuery: Sendable, Hashable { normalized, tokens, isEmpty }
    public struct PreparedText: Sendable, Hashable { title, content }   // normalised
    public func prepare(query: String) -> PreparedQuery
    /// The content also gets words rejoined across OCR line-break hyphens appended
    /// ("doku-\nmentów" → "dokumentów" and "doku-mentów"; "Bielsko-\nBiałej" → "Bielsko-Białej";
    /// letters required on both sides), so both the fragments and the whole word match.
    public func prepare(title: String, content: String) -> PreparedText
    public func score(_ query: PreparedQuery, in text: PreparedText) -> Int      // 0 = no match
    /// Result snippet: the first OCR line containing the whole query (several tokens), else each
    /// token in order; same folding as `score`. `pages` = each page's OCR text in page order.
    /// nil for a blank query or when no single line contains it (title-only match, phrase or
    /// hyphenated word broken across lines). The snippet starts at most `min(20, maxLength / 3)`
    /// characters before the hit, at the earliest whole word in that window (also on short lines),
    /// so the hit is on the first visible line; ≤ `maxLength` (≥ 20) characters plus "…" where cut.
    public func firstMatch(for query: PreparedQuery, inPages pages: [String], maxLength: Int = 80) -> SearchMatch?
    /// Same, with each page's normalised text supplied (must equal `normalize(pages[i])`) so callers
    /// can cache it; called at most once per page, in order, until a page contains the query.
    public func firstMatch(for query: PreparedQuery, inPages pages: [String], maxLength: Int = 80,
                           normalizedPage: (Int) -> String) -> SearchMatch?
}
public struct SearchMatch: Sendable, Hashable {
    public let pageIndex: Int               // 0-based
    public let snippet: String              // whitespace collapsed, starts a few words before the hit, "…" where cut
    public let highlight: Range<Int>?       // Character offsets of the hit in `snippet`
}
public enum SortOption: String, CaseIterable, Sendable, Codable {
    case dateModifiedDescending, dateCreatedDescending, titleAscending
}
/// Selected ids in selection order (library Select mode; Merge appends to the first selected).
public struct OrderedSelection<ID: Hashable & Sendable>: Sendable, Equatable {
    public private(set) var ids: [ID]
    public init(_ ids: [ID] = [])                          // duplicates removed, first occurrence kept
    public var count: Int; public var isEmpty: Bool; public var first: ID?
    public func contains(_ id: ID) -> Bool
    public func position(of id: ID) -> Int?               // 1-based (1 = selected first); nil = not selected
    public mutating func toggle(_ id: ID)
    public mutating func select(_ newIDs: [ID])
    public mutating func retain(only allowed: Set<ID>)    // drop ids that disappeared
    public mutating func removeAll()
}
/// How long Recently Deleted keeps a document. Days are 24-hour periods from the deletion, so time
/// zone and daylight-saving changes never shorten or extend it.
public struct DeletionRetention: Sendable, Equatable {
    public static let standard: DeletionRetention        // 30 days
    public let days: Int
    public init(days: Int)                                // < 1 counts as 1
    public func expiry(deletedAt: Date) -> Date
    public func isExpired(deletedAt: Date, now: Date) -> Bool          // now >= expiry
    /// Whole days left, rounded up ("30 days left" right after deleting, "1 day left" on the last
    /// day), clamped to 1...days (a deletedAt in the future shows `days`).
    public func daysRemaining(deletedAt: Date, now: Date) -> Int
}
```

### Storage
```swift
/// Files per page: <root>/<pageID>/original.jpg, processed.jpg, thumb.jpg, source.jpg (optional, imported photos only)
public struct PageImageStore: Sendable {
    public enum Kind: String, Sendable { case source, original, processed, thumb }
    public init(rootDirectory: URL)
    public static func defaultRoot() throws -> URL        // Application Support/Flatly/Pages (excluded from backup = false)
    public func url(for pageID: UUID, kind: Kind) -> URL
    /// Atomic. `createsPageFolder: false` (edits of an existing page) throws `.io` instead of
    /// re-creating the folder of a page deleted (and trashed) while it was being rendered.
    public func write(_ data: Data, for pageID: UUID, kind: Kind, createsPageFolder: Bool = true) throws
    public func read(for pageID: UUID, kind: Kind) throws -> Data
    public func exists(for pageID: UUID, kind: Kind) -> Bool
    public func delete(pageID: UUID) throws
    /// Renames the page folder into the hidden `<root>/.trash` (excluded from backup); call only
    /// after the page's deletion was saved. `emptyTrash()` erases the trash (best effort, keeps the
    /// `.trash` folder itself); safe at any time, even with an empty or unreadable library.
    public func moveToTrash(pageID: UUID) throws
    @discardableResult public func emptyTrash() -> Int
    public func allPageIDs() throws -> [UUID]                // never lists `.trash`
    /// Startup sweep: deletes page folders not in `knownPageIDs` and last modified before `cutoff`
    /// (younger ones may belong to a capture still being saved). Deletes nothing when
    /// `knownPageIDs` is empty (an unread library must never look like an empty one). Ignores `.trash`.
    @discardableResult
    public func removeOrphanedPages(keeping knownPageIDs: Set<UUID>, modifiedBefore cutoff: Date) throws -> [UUID]
}
```

### Signature
```swift
public struct SignaturePlacement: Sendable, Hashable, Codable {
    public var drawingData: Data          // PKDrawing.dataRepresentation()
    public var frame: CGRect              // normalised, top-left origin, relative to the *rotated, cropped* page image
    public init(drawingData: Data, frame: CGRect)
}
public struct SignatureRenderer: Sendable {
    public init()
    /// Renders the PKDrawing into a transparent CGImage of `size` pixels (aspect-fit). Ink keeps the
    /// colour it was drawn in, rendered in the light appearance, so it never flips in dark mode.
    public func render(drawingData: Data, size: CGSize) throws -> CGImage
    /// Composites the signature over `page` at `frame`.
    public func composite(_ placement: SignaturePlacement, onto page: CGImage) throws -> CGImage
}
/// Where a new signature first appears: a frame the size of `preferred` (top-left origin) kept
/// `margin` away from every OCR line box (Vision boxes of the same processed page), closest to
/// `preferred`'s centre (ties: lower, then further right). `preferred` when already clear, when
/// there are no lines, or when no clear spot exists.
public struct SignatureSpotFinder: Sendable {
    public init()
    public func frame(near preferred: CGRect, avoiding lines: [OCRLine], margin: CGFloat = 0.01) -> CGRect
}
```

### Errors
`FlatlyCoreError` (`notImplemented`, `invalidImage`, `decodingFailed`, `encodingFailed`,
`invalidQuadrilateral`, `io`, `processingFailed`) carries technical detail only. FlatlyCore has
no string catalog, so the app adds a retroactive `LocalizedError` conformance
(`FlatlyApp/Services/FlatlyCoreError+LocalizedError.swift`) whose exhaustive switch gives every
case a localized sentence for alerts; a new case must get one there.

## 2. App data model (SwiftData, `FlatlyApp/Persistence/`)

```
Folder       id, name, createdAt, documents (nullify)
ScanDocument id, title, createdAt, modifiedAt, folder?, pages (cascade), ocrText (denormalised, for search),
             deletedAt? (set while in Recently Deleted; optional, so lightweight migration adds it as nil)
ScanPage     id, index, document?, createdAt, recipeData (PageRenderRecipe JSON), ocrData (OCRResult JSON),
             ocrText, hasSource (Bool: source.jpg exists), detectedQuadData (Quadrilateral JSON, imported only),
             widthPx, heightPx (processed image size)
```
Images live on disk via `PageImageStore`, keyed by `ScanPage.id`:
- `source.jpg`   — the image edges are adjusted on: the untouched imported or Offscan-camera photo (≤ 3500 px; camera photos keep only the EXIF `FocalLenIn35mmFilm` tag, which `finishImport` / `readjustCorners` pass to `PerspectiveCorrector`), or (Apple-scanner and imported-PDF pages) a copy of `original.jpg` made on the first "Adjust Edges", so edges can be refined repeatedly without compounding loss.
- `original.jpg` — perspective-corrected, unfiltered, unrotated page (what camera/VisionKit or the corrector produced).
- `processed.jpg`— `PageRenderer.render(original, recipe)`. This is what the UI shows and what gets exported.
- `thumb.jpg`    — thumbnail of processed.

`DocumentStore` (`@MainActor @Observable final class`) is the single mutation API. It owns the
`ModelContext` and exposes `documents` (the library), `recentlyDeleted` (most recently deleted first) and
`folders`. Views use it via `@Environment(DocumentStore.self)`.
`page(id:)` re-resolves a page after an `await` (never hold model objects across background work);
`clearOCR` marks a page's text as pending.
- Deleting a document moves it to Recently Deleted: `moveToRecentlyDeleted(_:)` sets `deletedAt` (folder, pages,
  images and dates kept), `restore(_:)` clears it (a document whose folder was deleted meanwhile returns
  unfiled), `deletePermanently(_:)` erases documents with their pages and images, and
  `purgeExpiredDeletions(now:retention:)` erases the ones older than `DeletionRetention.standard` (at launch and
  when Recently Deleted opens). Trashed documents are left out of `documents`, `document(id:)`, `page(id:)` and
  search, so the editor, export, OCR and search never see them; folder counts skip them.
- Saves re-run the fetches only when documents or folders are created or deleted, a document is moved to or
  restored from Recently Deleted, a folder is renamed or a document moved; other mutations re-sort `documents`
  in memory (model objects are observable).
- Multi-item changes take one save: `addPages(_:to:)`, `deletePages(_:)`, `move(_:to:)`,
  `moveToRecentlyDeleted(_:)`, `restore(_:)`, `deletePermanently(_:)` (documents), `merge(_:into:)` (pages
  appended in order, keeping their ids and files). Merge saves the
  re-parenting first; the emptied sources are deleted by the first save that succeeds (that one, or
  a later one after a failure), and only while they are still empty, so a delete never cascades to a
  page that did not move. Image folders of deleted pages are moved to the image store's trash right
  after the deletion has been saved (one rename each, on the main actor) and erased off the main actor.
- `ScanDocument.ocrText` (search text) is rebuilt from the pages in display order whenever a page's
  text, the set of pages (delete, merge) or their order changes, so search never finds removed text.
- A failed save is not rolled back: the changes stay in the context and are written by the next
  successful save; `saveFailureNeedsAttention` makes RootView show an alert (Try Again =
  `retryFailedSave()`, also retried when the scene goes to the background). It is raised once per
  run of failures, and again for every new scan or import (`createDocument`, `addPages`) that can't be
  saved after the user dismissed it; background saves (OCR) never repeat it. `hasUnsavedChanges` is
  true while such changes are pending.
- `pageMaintenanceSnapshot()` reads every page id (`known`, Recently Deleted included) and the pages with pending text on a
  short-lived background context; nil when the fetch fails. `warmSearch()` pre-normalises search text;
  `searchMatch(for:query:)` gives a result row's snippet (cached by `LibrarySearch`).

`ScanProcessor` (actor, `FlatlyApp/Services/`) wraps FlatlyCore and the image files. Every operation is
`nonisolated` and `@concurrent` (behind `#if hasAttribute(concurrent)`), so Vision and Core Image work runs
on the cooperative pool in parallel and never on the caller's (main) actor; `project.yml` pins
`SWIFT_APPROACHABLE_CONCURRENCY=NO` and `SWIFT_DEFAULT_ACTOR_ISOLATION=nonisolated` to keep it that way.
`DocumentAssembler` (main actor) turns its results into pages (`append(_:to:title:)`). Editors use
`applyDeferringOCR` / `readjustCornersDeferringOCR` (re-render now, clear stale text) followed by
`scheduleOCR(forPageID:)`, which keeps one pending recognition per page: each edit cancels the previous one
and waits 1.5 s, so trying several filters recognises only the final image. Post-scan, post-import and
startup OCR run in utility-priority tasks; an export's wait for pending text keeps user-initiated priority.
A page with `ocrData == nil` is "recognising"; failed OCR stores `OCRResult.empty`.
Recognitions of one page may overlap and finish in any order, so `DocumentAssembler` counts re-renders per page
and drops any result computed on an image that has since been replaced. Edit renders of one page, by contrast,
run one after another: `DocumentAssembler` (`@Observable`) queues each `applyDeferringOCR` /
`readjustCornersDeferringOCR` behind the page's previous one (never cancelled mid-render), and
`isRendering(pageID:)` keeps a re-opened editor's "Updating page…" overlay up (tools disabled) while a render
started before Back is still running. `readjustCornersDeferringOCR` reads the recipe when its render starts.
Edit writes (`ScanProcessor`: re-corrected original, promoted source, processed, thumb) pass
`createsPageFolder: false`, so a render that outlives its page fails instead of restoring the trashed folder.

`AppServices` (environment) holds `store`, `processor`, `assembler`; `ImageCache` (environment) caches decoded
page images in two budgets (50 MB thumbnails, 100 MB pages, so editor pages never evict library thumbnails) —
call `invalidate(pageID:)` after every re-render. `AppLockManager` and `QuickActionInbox` are injected separately.

UserDefaults keys: `appLockEnabled`, `defaultFilter` (ScanFilter raw), `librarySort` (SortOption raw),
`exportFormat`, `exportPageSize` (default `PageSizeOption.regionDefault`: Letter in US-Letter regions, else A4),
`exportCompression`, `savedSignature` (PKDrawing data; replaced only while the canvas's "Save as My Signature" /
"Replace Saved Signature" switch is on, which starts on only when nothing is saved yet),
`signatureInk` (`SignatureInk` raw: `blue` default / `navy` / `black`; the colour lives in the drawing's strokes),
`cameraMode` (`flatly` default / `apple`; Settings' Advanced section subtitles each option with `CameraMode.summary`), `autoCapture` (Bool, default true), `cameraFlash` (`auto`/`on`/`off`),
`reviewEdgesAfterScan` (Bool, default false: Offscan camera shows every page in the corner editor; in Advanced,
under the camera choice, only while the Offscan camera is chosen),
`didShowEditHint` (Int: how often the document screen's edit hint was shown).

## 3. Pipelines

**Camera scan (Offscan camera, default)**: `ScanCaptureSheet` reads `cameraMode`. `CaptureSessionPipeline`
(AVCaptureSession on a private serial queue; photo output + a video data output delivering native YUV 4:2:0
frames, BGRA only as a fallback) analyses ~9 frames/s with `DocumentDetector.detectLive` + `QuadStabilityTracker`;
`CameraController` (main actor, its pipeline created lazily on first use) draws the smoothed quad
(`CameraOverlayGeometry`: normalised upright quad → aspect-fill rect of the preview), shows "Move closer" while
`isSheetTooSmall`, and auto-captures when stable (then tracker reset, 1.2 s cooldown, and it waits until the sheet
moves away or disappears). Every photo's encoded data → `CameraPageQueue` → `ScanProcessor.stageImport(imageData:)`
in a serial background chain while shooting: the full photo (≤ 3500 px, plus its EXIF focal length) is stored as
`source` and re-detected at full resolution. The queue keeps only page id + `DetectedDocument` + a ≤ 240 px
thumbnail per photo. For 3 s after each photo the hint becomes Undo (only while that photo is still in the
session: deleting it in the sheet brings the hint back); the thumbnail opens `CapturedPagesSheet`
(opaque, delete pages, Keep Scanning in the bar, a full-width Finish Scanning at the bottom) over the live camera.
Only Done ends shooting, or Finish Scanning (same condition: a page and no photo still on its way), which closes
the sheet and runs Done from the sheet's `onDismiss` (auto-capture stays paused meanwhile): pages whose sheet was found by
segmentation are corrected with their detected edges without review (`StagedPageReview.autoAccept`); the others
(rectangle / full-frame detections), or every page with `reviewEdgesAfterScan`, are shown in `CornerAdjustView`
(≤ 2000 px; "Use All" accepts the rest as detected; Delete Page drops one) → `finishImport` →
`DocumentAssembler.append` → OCR in the background. Camera pages thus have a `source` and can be re-adjusted in
either direction, any number of times. Camera orientation follows the interface orientation.
The session stops while the app is locked or in the background and restarts after unlock (`stop()` always
calls `stopRunning()` on a configured session: an interrupted one reports `isRunning == false` but would
otherwise resume by itself behind the lock or during the review); auto-capture pauses
under dialogs, the pages sheet and while the scene is inactive (the shutter keeps working). Interruptions and
runtime errors (`CameraInterruption`) dim the preview, show the reason and disable the shutter; after a runtime
error the session restarts once (at most every 3 s), otherwise `.failed` is shown. The screen stays awake only
for 2 minutes after opening or the last capture. With VoiceOver, settled detection changes and every capture are
announced. DEBUG builds with the demo library (`FLATLY_UI_TESTING=1` + `FLATLY_DEMO_DATA=1`) run `CameraController`
on `DemoCameraFeed` instead (a desk photo, live detection through a real `QuadStabilityTracker` whose steady period
restarts before auto-capture, the still's JPEG on the shutter, staged by `CameraPageQueue` with the sheet's known
corners): no pipeline, no camera permission, and the camera
counts as available, so the simulator screenshots show Offscan's scanner. Release builds are unchanged.

**Camera scan (Apple scanner, optional)**: VNDocumentCameraViewController → N UIImages (already corrected) → for each:
`ImageCodec.jpegData` → store `original` → `PageRenderer.render(recipe default .color)` → store `processed`
→ thumbnail → `TextRecognizer.recognize(processed)` → save OCR. Document title = `DocumentNaming.defaultTitle`.
All processing in `ScanProcessor` (background actor); UI shows "Processing page x of y" with Stop, which keeps
the pages finished so far (the page in progress finishes) and drops the rest. Such pages get a `source` (copy of
`original`) on their first "Adjust Edges", so their edges can only be tightened. Devices without a camera
(simulator) always use this flow, which shows `CameraUnavailableView` (+ debug "Use Sample Page").

**Import (Photos / Files)**: decode (`ImageCodec`, EXIF applied, downsample to ≤ 3500 px) → store `source`
→ `DocumentDetector.detect` → `StagedPageReview` → `CornerAdjustView` pre-filled with the quad, shown at ≤ 2000 px
(user drags 4 handles; loupe magnifies under the finger; "Use All" accepts the rest as detected) →
`PerspectiveCorrector.correct` → same as camera from "store original". Files imports are opened first
(`FileImportSelection`, "Opening files…" with Cancel, no confirmation since nothing is staged yet): a
multi-page TIFF becomes one item per page
(`stageImport(imageData:index:)`); each PDF is copied to `tmp/FlatlyImports` (deleted when the import flow ends, at the next Files import and
at launch) and expanded into its pages, which
skip the corner review and are rasterized in order (`ScanProcessor.preparePDFPage`, `PDFPageRasterizer`, filter
`.original`) behind "Preparing page x of y". Every "Preparing page x of y" screen offers Cancel, also while a page
is still loading (e.g. an iCloud photo); with several pages it asks first (Discard All Pages / Continue). The
confirmation lives on `StagedPageReview`'s root, so it survives the page finishing meanwhile, and while it is open
the review holds (no save, no corner editor) until Continue. PDF pages have no `source` (like Apple-scanner
pages). A new document from a picked PDF is titled after the file; locked or corrupt PDFs are listed in the
failure alert.

**Edit page**: change recipe (filter / rotation / crop / signature) → re-render processed + thumb → re-run OCR
(rotation/crop change coordinates; debounced per page, see `scheduleOCR`). Adjust edges (any page): re-run corrector
on `source` (shown at ≤ 2000 px); drops crop and signature. The pager decodes the 2000 px image only for the shown
page and its two neighbours; other pages show their thumbnail. "Apply to All" (filter bar) re-renders every other
page with the shown page's filter, one page at a time behind a cancellable overlay (Cancel or leaving the
editor; cancellation only between pages), then recognises the changed pages' text in the background. The filter
bar shows four equal tiles across the width (the top of the page at 400 px, captions describing the result). Crop
and Adjust Edges each show a one-line instruction so the two are told apart. A new signature starts near the
bottom right, moved off recognised text (`SignatureSpotFinder`). The signature canvas has an Ink Color row
(`SignatureInk`); switching recolours the strokes already drawn, so a signature is always one colour.

**Recognised text**: `OCRTextView` ("Recognized Text") shows `OCRResult.readableText` (joined paragraphs) with a
divider and "Page N" header per page; its bottom bar offers Copy All (briefly "Copied", with a VoiceOver
announcement) and Share, and the top bar keeps only the More menu ("Run Text Recognition Again"). Search and the PDF text layer keep using `OCRResult.text`. Each
page's readable text is memoised by `ReadableTextCache` (keyed by its OCR data), so body passes don't re-decode or
re-flow it.

**Export**: for each page, one at a time: load processed, `ImageTransforms.resized(maxDimension: compression.maxPixelDimension)`,
pass with OCR → `PDFExporter.writePDF` (streams into the temp file) / `JPEGExporter` → share sheet / `fileExporter`.
Never collect all pages' images first: one decoded page is 15–25 MB, so a 60-page document would need over 1 GB.
A PDF export first waits for pages whose text is still pending (`DocumentAssembler.recognizePendingText`), so
"Share PDF" right after a scan still produces a searchable file. Each export writes into its own folder under
`tmp/FlatlyExports`; a failed or cancelled export leaves nothing behind. Temporary exports are deleted at the next
export, when the Save to Files picker closes, when a document is deleted (all of them, so no copy outlives it) and
at launch; share-sheet files stay until then (AirDrop and Copy may read them after the sheet closes).
One-tap "Share PDF" (`QuickPDFShareModifier`: document screen, library Select mode) builds each document's PDF with
the last-used `exportPageSize` / `exportCompression` behind a cancellable "Exporting 2 of 3…" overlay and shares
them in one sheet. The Export sheet shows a header (first page, title, page count) and pins Share / Save to Files.
For PDF it has a Password row (Off / On) that pushes `PDFPasswordView`: typed twice, printable ASCII only
(`PDFExporter.isSupportedPassword`), applied with Set (the only trailing item), removable. The password lives in
the sheet's `@State` only (never stored) and is passed through `ExportService.prepareRequest(…password:)` →
`ScanProcessor.exportPDF(…password:)` → `PDFExporter.writePDF`; one-tap Share PDF and batch exports never encrypt.

**Search**: `DocumentStore.documents(in:…query:…)` → `LibrarySearch` (app, `Services/`), which caches every document's
`SearchMatcher.PreparedText` until its title or OCR text changes and scores the prepared query against it, in memory.
When the search field opens, `DocumentStore.warmSearch()` normalises documents without an up-to-date entry in a
detached task (`LibrarySearch.warm`), so launches without a search cost nothing. Results are `SearchResultRow` list
rows under an "N results across all folders" header (small first-page thumbnail, title, the matching line with the
hit bold on an accent tint, "Page N · date"); rows on screen show `SearchMatcher.firstMatch` from
`DocumentStore.searchMatch(for:query:)`:
`LibrarySearch` normalises each page's text lazily, at most once until that page's text changes (not in `warm`, which
would fault every page in on the main actor), and reuses the last match per document while the query and the pages
are unchanged, so body passes normalise nothing. The floating Scan pill hides while searching.

**Library**: the root shows a "Recent" strip (6 most recently modified documents across folders) once something is
filed; its cards keep the same thumbnail size and allow one more title line than grid cards (they are narrower).
Sort (like Select) is disabled when nothing is listed. Select mode
turns cards into toggles (`OrderedSelection`; selected cards and search rows show their position in selection
order, `N.circle.fill` up to 50, and say "number N in the selection" to VoiceOver), hides Recent and Folders, and
shows a labelled bottom bar
(`SelectionBarLabel`: icon over caption): Share PDF, Move to Folder…, Merge (enabled from two documents; pages
appended to the first selected document, in selection order; `DocumentStore.merge`) and Delete (last, in red).
The Merge and Delete confirmations are anchored to their buttons. Deleting (context menu, Select mode, document
screen) moves documents to Recently Deleted and clears temporary exports. While anything is there, the Folders
section ends with a Recently Deleted row (`RecentlyDeletedFolderRow`, also shown with no folders) that pushes
`RecentlyDeletedView`: rows with thumbnail, title and "N days left"; tapping a row offers Restore / Delete Now, and
the bottom bar has Delete All (confirmed) and Restore All. Dialog titles and accessibility values with
counts use plural catalog variants, never `^[…](inflect: true)` markup (which `confirmationDialog` shows raw;
`scripts/check-localization.sh` rejects it).

**App lock**: `AppLockManager` (LAContext). Enabled flag in UserDefaults. Locks on launch and whenever
the scene goes to background; `LockWindowPresenter` shows `LockScreenView` in its own window above everything,
full-screen covers included (camera, import, crop), until `evaluatePolicy` succeeds. While the scene is inactive
(app switcher, Control Center) `isShielded` covers the UI with an opaque privacy shield, so the app-switcher card
and iOS's snapshot show no content. Turning the lock on **or off** requires device-owner authentication (off is
allowed without a prompt only when the device has no passcode). The Offscan camera stops behind the lock.
The lock follows the scene twice over: `LockWindowPresenter` observes UIScene will-deactivate (shield),
did-enter-background (lock, synchronously, before the snapshot) and did-activate (unshield, once-per-foreground
unlock prompt), which keep arriving while a full-screen cover stops SwiftUI from updating RootView; RootView's
scene-phase handler calls the same idempotent `AppLockManager` methods (`shieldIfEnabled`,
`sceneDidEnterBackground`, `sceneDidBecomeActive`). Without biometrics the Settings toggle reads "Require Passcode".

**Startup**: `FlatlyApp` opens `AppServices`; if the library can't be opened it shows `StartupErrorView` instead of
crashing: it says the documents are still on the device, how to free space (Settings > General > iPhone / iPad
Storage) and not to delete the app, offers Try Again, and shows the error domain and code only after Show Details.
`AppServices.runStartupMaintenance()` (from RootView's `.task`, which restarts after every full-screen cover) runs
once per `AppServices`; later calls return at once. In DEBUG demo mode it first seeds the demo library (only when
the library and Recently Deleted are empty). It then erases documents whose time in Recently Deleted has expired
(`purgeExpiredDeletions`, before the snapshot, so their pages no longer count as known). It empties
the image store's trash at every launch, even when the library is empty or unreadable (it holds only folders of
pages whose deletion was saved), and takes `pageMaintenanceSnapshot()`; unless it is nil or the store has unsaved
changes (`hasUnsavedChanges`: the snapshot sees only saved rows), `PageImageStore.removeOrphanedPages` sweeps image
folders older than 10 minutes that no page row knows, then text still pending from a previous run is recognised at
utility priority. Leftover temporary exports and PDF import copies are cleared at launch.

**Home Screen quick action**: "Scan Document" (`flatly.quickaction.scan`, `UIApplicationShortcutItems` in
`project.yml`, title localized in `InfoPlist.xcstrings`). `AppDelegate` records a cold-launch shortcut and installs
`SceneDelegate` for warm launches (ignored while something is presented); both write to `QuickActionInbox`, which the
root `LibraryView` consumes once the app is unlocked: it pops to the root and opens the camera.

**Privacy manifest**: `FlatlyApp/Resources/PrivacyInfo.xcprivacy` declares no tracking, no tracking domains, no
collected data, and the required-reason APIs used: UserDefaults (CA92.1, own settings) and file timestamps (C617.1,
startup sweep of the app's own page folders). Adding another required-reason API (e.g. disk space, system boot
time) means adding it there; `scripts/check-all.sh` lints the file with `plutil`.

## 4. Coordinate conventions (read twice)
- Vision & PDF & `Quadrilateral` & `OCRLine.boundingBox`: normalised, **bottom-left** origin.
- SwiftUI/UIKit & `PageRenderRecipe.cropRect` & `SignaturePlacement.frame`: normalised, **top-left** origin.
- Convert with `Quadrilateral.flippedVertically()` / `y' = 1 - y - height`.
- CIImage extent is bottom-left origin in pixels.

## 5. Toolchain constraints on the dev machine
No Xcode, only Command Line Tools. Consequences handled by `scripts/`:
- Swift Testing macro plugin must be loaded explicitly; tests must run as arm64 (`arch -arm64`) or Vision fails.
- SwiftData / `#Predicate` macros unavailable → confined to `FlatlyApp/Persistence/`, replaced by
  `Tools/Typecheck/PersistenceStubs.swift` during `scripts/typecheck-app.sh`. Keep the stubs' API identical.
- App code is type-checked against the Mac Catalyst SDK (macOS 26.5 SDK, target `arm64-apple-ios17.0-macabi`).
  `VNDocumentCameraViewController` is available there, so camera code type-checks too.

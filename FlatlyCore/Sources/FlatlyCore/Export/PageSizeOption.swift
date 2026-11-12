import Foundation
import CoreGraphics

/// Target PDF page size.
public enum PageSizeOption: String, CaseIterable, Sendable, Codable, Hashable {
    case a4
    case letter
    /// Page takes the image's aspect ratio; width is fixed to A4 width (595 pt).
    case fitToContent

    /// Portrait page size in PDF points, or nil for `fitToContent`.
    public var portraitPointSize: CGSize? {
        switch self {
        case .a4: return CGSize(width: 595.276, height: 841.89)
        case .letter: return CGSize(width: 612, height: 792)
        case .fitToContent: return nil
        }
    }

    /// Regions whose customary paper size is US Letter (CLDR supplemental paperSize data).
    private static let letterRegions: Set<String> = ["BZ", "CA", "CL", "CO", "CR", "GT", "MX", "NI", "PA", "PH", "PR", "SV", "US", "VE"]

    /// The customary page size for an ISO 3166 region code: `.letter` in US-Letter regions,
    /// otherwise `.a4`. `nil` or unknown regions give `.a4`. The code is compared case-insensitively.
    public static func defaultSize(forRegion regionCode: String?) -> PageSizeOption {
        guard let code = regionCode?.uppercased(), letterRegions.contains(code) else { return .a4 }
        return .letter
    }

    /// The customary page size for the user's current region (`Locale.current`). Used as the
    /// default export page size.
    public static var regionDefault: PageSizeOption {
        defaultSize(forRegion: Locale.current.region?.identifier)
    }
}

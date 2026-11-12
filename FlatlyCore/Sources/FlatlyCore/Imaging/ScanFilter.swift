import Foundation

/// Colour treatment applied to a page.
public enum ScanFilter: String, CaseIterable, Sendable, Codable, Hashable {
    /// Untouched.
    case original
    /// Enhanced colour: paper-background estimation flattens uneven light and colour casts so
    /// the sheet becomes white; ink is darkened with an S-curve; colours are preserved.
    case color
    /// Same flattening as `color`, then luminance.
    case grayscale
    /// Shadow removal + adaptive threshold → crisp black text on white.
    case blackAndWhite
}

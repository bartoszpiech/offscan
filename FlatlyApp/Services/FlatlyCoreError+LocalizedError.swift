import Foundation
import FlatlyCore

/// User-facing, localized descriptions for FlatlyCore errors, so alerts that show
/// `error.localizedDescription` read as a sentence instead of Foundation's
/// "FlatlyCore.FlatlyCoreError error N" fallback.
///
/// FlatlyCore has no string catalog, so the conformance lives in the app. The technical
/// associated strings (paths, underlying errors) are for debugging only and never reach the UI.
/// The switch is exhaustive on purpose: a new `FlatlyCoreError` case must get a description here.
extension FlatlyCoreError: @retroactive LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidImage, .decodingFailed:
            String(localized: "The image could not be read.")
        case .encodingFailed:
            String(localized: "The image could not be saved.")
        case .invalidQuadrilateral:
            String(localized: "The corners must form a convex shape.")
        case .io:
            String(localized: "The file could not be read or saved. If storage is almost full, free up some space and try again.")
        case .processingFailed, .notImplemented:
            String(localized: "The page could not be processed.")
        }
    }
}

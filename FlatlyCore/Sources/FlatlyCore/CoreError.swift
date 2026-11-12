import Foundation

/// Errors shared by FlatlyCore services.
///
/// User-facing, localized descriptions live in the app
/// (`FlatlyApp/Services/FlatlyCoreError+LocalizedError.swift`); add one there for any new case.
public enum FlatlyCoreError: Error, Sendable, Equatable {
    case notImplemented(String)
    case invalidImage
    case invalidQuadrilateral
    case processingFailed(String)
    case encodingFailed
    case decodingFailed
    case io(String)
}

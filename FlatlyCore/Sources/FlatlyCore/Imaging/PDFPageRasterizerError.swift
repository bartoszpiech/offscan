import Foundation

/// Errors of `PDFPageRasterizer`.
public enum PDFPageRasterizerError: Error, Sendable, Equatable {
    /// The file is missing, isn't a PDF, or has no pages.
    case unreadable
    /// The PDF needs a password to be opened.
    case passwordProtected
    /// The requested page index doesn't exist.
    case pageOutOfRange
    /// The page has an empty box, or drawing it failed.
    case renderFailed
}

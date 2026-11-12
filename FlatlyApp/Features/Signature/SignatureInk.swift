import SwiftUI
import UIKit
import PencilKit

/// Ink colour for drawing a signature: ballpoint blue (the default: contracts are often signed in
/// blue so the original can be told from a copy), navy or black. Remembered per device in
/// UserDefaults under `signatureInk` (the raw value).
///
/// The colour lives in the `PKDrawing`'s strokes, so the saved signature and every placed signature
/// keep it: `SignatureRenderer` draws the strokes as they are (light appearance). Applying a colour
/// recolours the whole drawing, so a signature is always one colour.
enum SignatureInk: String, CaseIterable, Identifiable {
    case blue, navy, black

    static let storageKey = "signatureInk"

    /// The chosen ink, or blue when nothing (or something unknown) is stored.
    static var current: SignatureInk {
        UserDefaults.standard.string(forKey: storageKey).flatMap(SignatureInk.init(rawValue:)) ?? .blue
    }

    var id: String { rawValue }

    /// Fixed sRGB values, never dynamic colours: the paper is always white, in either appearance.
    var uiColor: UIColor {
        switch self {
        case .blue:
            return UIColor(red: 0.10, green: 0.27, blue: 0.75, alpha: 1)
        case .navy:
            return UIColor(red: 0.07, green: 0.12, blue: 0.38, alpha: 1)
        case .black:
            return UIColor.black
        }
    }

    var color: Color { Color(uiColor: uiColor) }

    /// Localized name (VoiceOver label of the swatch).
    var name: String {
        switch self {
        case .blue:
            return String(localized: "Blue", comment: "Signature ink color")
        case .navy:
            return String(localized: "Navy", comment: "Signature ink color")
        case .black:
            return String(localized: "Black", comment: "Signature ink color")
        }
    }

    /// The canvas pen in this colour (4 pt).
    var tool: PKInkingTool { PKInkingTool(.pen, color: uiColor, width: 4) }

    /// `drawing` with every stroke in this colour (ink type and shape unchanged).
    func applied(to drawing: PKDrawing) -> PKDrawing {
        var copy = drawing
        copy.strokes = copy.strokes.map { stroke in
            var recoloured = stroke
            recoloured.ink = PKInk(recoloured.ink.inkType, color: uiColor)
            return recoloured
        }
        return copy
    }
}

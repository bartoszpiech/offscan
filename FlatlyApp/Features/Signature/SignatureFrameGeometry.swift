import CoreGraphics

/// Pure geometry for a signature frame: normalised (unit square, top-left origin) rect on a page
/// whose pixel aspect is `pageAspect` (w/h), holding a drawing whose aspect is `drawingAspect`.
/// The frame always keeps the drawing's aspect in *pixels* and stays inside the page.
struct SignatureFrameGeometry {
    let pageAspect: CGFloat
    let drawingAspect: CGFloat

    static let minimumWidth: CGFloat = 0.05

    /// Normalised height for normalised `width` keeping the drawing's pixel aspect.
    func height(forWidth width: CGFloat) -> CGFloat {
        guard drawingAspect > 0 else { return width }
        return width * pageAspect / drawingAspect
    }

    /// Largest normalised width so that both width and height fit in the page.
    var maximumWidth: CGFloat {
        guard pageAspect > 0 else { return 1 }
        return min(1, drawingAspect / pageAspect)
    }

    /// Default placement: 35 % of the page width, centred in the bottom-right quarter.
    var initialFrame: CGRect {
        var w = min(0.35, maximumWidth)
        var h = height(forWidth: w)
        if h > 0.5 {   // very tall signature: keep it within the quarter
            w *= 0.5 / h
            h = 0.5
        }
        return clamped(CGRect(x: 0.75 - w / 2, y: 0.75 - h / 2, width: w, height: h))
    }

    /// Resizes `frame` to `width` (clamped) keeping its centre, then keeps it inside the page.
    func resized(_ frame: CGRect, toWidth width: CGFloat, anchor: Anchor = .center) -> CGRect {
        let w = min(max(width, Self.minimumWidth), maximumWidth)
        let h = height(forWidth: w)
        let origin: CGPoint
        switch anchor {
        case .center: origin = CGPoint(x: frame.midX - w / 2, y: frame.midY - h / 2)
        case .topLeft: origin = frame.origin
        }
        return clamped(CGRect(origin: origin, size: CGSize(width: w, height: h)))
    }

    /// Scales `frame` about its centre.
    func scaled(_ frame: CGRect, by factor: CGFloat) -> CGRect {
        resized(frame, toWidth: frame.width * factor)
    }

    /// Moves `frame` by a normalised offset, staying inside the page.
    func moved(_ frame: CGRect, by delta: CGSize) -> CGRect {
        clamped(frame.offsetBy(dx: delta.width, dy: delta.height))
    }

    /// Keeps the frame inside the unit square.
    func clamped(_ frame: CGRect) -> CGRect {
        var r = frame
        r.size.width = min(r.width, 1)
        r.size.height = min(r.height, 1)
        r.origin.x = min(max(r.minX, 0), 1 - r.width)
        r.origin.y = min(max(r.minY, 0), 1 - r.height)
        return r
    }

    enum Anchor { case center, topLeft }
}

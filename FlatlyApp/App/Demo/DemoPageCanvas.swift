#if DEBUG
import UIKit
import FlatlyCore

/// Drawing surface for one synthetic demo page (UIKit context: top-left origin, pixels).
/// Text drawn with `text` / `paragraph` / `table` is recorded as `OCRLine`s, so a seeded page
/// carries the text a perfect OCR pass would find on it.
final class DemoPageCanvas {
    enum Face { case sans, serif, mono }

    /// A table column: title, width in pixels and alignment of its cells.
    struct Column {
        let title: String
        let width: CGFloat
        var align: NSTextAlignment = .left
    }

    let size: CGSize
    let context: CGContext
    private(set) var lines: [OCRLine] = []

    init(size: CGSize, context: CGContext) {
        self.size = size
        self.context = context
    }

    // MARK: Colours

    static var ink: UIColor { UIColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1) }
    static var gray: UIColor { UIColor(white: 0.40, alpha: 1) }
    static var rule: UIColor { UIColor(white: 0.74, alpha: 1) }
    static var tint: UIColor { UIColor(white: 0.93, alpha: 1) }
    static var blueInk: UIColor { UIColor(red: 0.09, green: 0.17, blue: 0.56, alpha: 0.88) }

    // MARK: Text

    func font(_ face: Face, _ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        let base: UIFont
        switch face {
        case .sans: base = .systemFont(ofSize: size, weight: weight)
        case .mono: base = .monospacedSystemFont(ofSize: size, weight: weight)
        case .serif:
            let system = UIFont.systemFont(ofSize: size, weight: weight)
            base = system.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? system
        }
        return base
    }

    /// Draws one line of text. `x` is the left edge, centre or right edge depending on `align`;
    /// `y` is the top of the line. Returns the drawn rectangle.
    @discardableResult
    func text(
        _ string: String,
        x: CGFloat,
        y: CGFloat,
        size: CGFloat,
        weight: UIFont.Weight = .regular,
        face: Face = .sans,
        color: UIColor = DemoPageCanvas.ink,
        align: NSTextAlignment = .left,
        kern: CGFloat = 0,
        recognized: Bool = true
    ) -> CGRect {
        let attributes = textAttributes(size: size, weight: weight, face: face, color: color, kern: kern)
        let nsString = string as NSString
        let measured = nsString.size(withAttributes: attributes)
        let left: CGFloat
        switch align {
        case .center: left = x - measured.width / 2
        case .right: left = x - measured.width
        default: left = x
        }
        nsString.draw(at: CGPoint(x: left, y: y), withAttributes: attributes)
        let rect = CGRect(x: left, y: y, width: measured.width, height: measured.height)
        if recognized { record(string, in: rect) }
        return rect
    }

    /// Word-wraps `string` into `width`. Continuation lines start `indent` pixels further right
    /// (a hanging indent for numbered clauses). Returns the y just below the last line.
    @discardableResult
    func paragraph(
        _ string: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        size: CGFloat,
        weight: UIFont.Weight = .regular,
        face: Face = .sans,
        color: UIColor = DemoPageCanvas.ink,
        indent: CGFloat = 0,
        lineSpacing: CGFloat = 1.38
    ) -> CGFloat {
        let attributes = textAttributes(size: size, weight: weight, face: face, color: color, kern: 0)
        let lineHeight = font(face, size, weight).lineHeight * lineSpacing
        var lineTop = y
        var current = ""
        var isFirstLine = true
        func flush() {
            guard !current.isEmpty else { return }
            text(current, x: isFirstLine ? x : x + indent, y: lineTop, size: size, weight: weight, face: face, color: color)
            lineTop += lineHeight
            current = ""
            isFirstLine = false
        }
        for word in string.split(separator: " ", omittingEmptySubsequences: true) {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            let available = isFirstLine ? width : width - indent
            if !current.isEmpty, (candidate as NSString).size(withAttributes: attributes).width > available {
                flush()
                current = String(word)
            } else {
                current = candidate
            }
        }
        flush()
        return lineTop
    }

    /// A table with a tinted header row and a rule under every row. Returns the y below it.
    @discardableResult
    func table(
        x: CGFloat,
        y: CGFloat,
        columns: [Column],
        rows: [[String]],
        fontSize: CGFloat = 19,
        rowHeight: CGFloat = 42,
        headerFill: UIColor = DemoPageCanvas.tint,
        boldRows: Set<Int> = [],
        verticalRules: Bool = true
    ) -> CGFloat {
        let width = columns.reduce(0) { $0 + $1.width }
        fill(CGRect(x: x, y: y, width: width, height: rowHeight), headerFill)
        let lineHeight = font(.sans, fontSize, .regular).lineHeight
        func drawRow(_ cells: [String], top: CGFloat, weight: UIFont.Weight, color: UIColor) {
            var left = x
            for (column, cell) in zip(columns, cells) {
                let anchor: CGFloat
                switch column.align {
                case .right: anchor = left + column.width - 12
                case .center: anchor = left + column.width / 2
                default: anchor = left + 12
                }
                if !cell.isEmpty {
                    text(cell, x: anchor, y: top + (rowHeight - lineHeight) / 2, size: fontSize, weight: weight, color: color, align: column.align)
                }
                left += column.width
            }
        }
        drawRow(columns.map(\.title), top: y, weight: .semibold, color: Self.ink)
        var top = y + rowHeight
        for (index, row) in rows.enumerated() {
            drawRow(row, top: top, weight: boldRows.contains(index) ? .bold : .regular, color: Self.ink)
            top += rowHeight
            line(CGPoint(x: x, y: top), CGPoint(x: x + width, y: top), width: 1.2)
        }
        stroke(CGRect(x: x, y: y, width: width, height: top - y), Self.rule, width: 1.5)
        if verticalRules {
            var left = x
            for column in columns.dropLast() {
                left += column.width
                line(CGPoint(x: left, y: y), CGPoint(x: left, y: top), width: 1.2)
            }
        }
        return top
    }

    // MARK: Shapes

    func fill(_ rect: CGRect, _ color: UIColor, radius: CGFloat = 0) {
        color.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
    }

    func stroke(_ rect: CGRect, _ color: UIColor, width: CGFloat = 1.5, radius: CGFloat = 0, dash: [CGFloat] = []) {
        let path = UIBezierPath(roundedRect: rect.insetBy(dx: width / 2, dy: width / 2), cornerRadius: radius)
        path.lineWidth = width
        if !dash.isEmpty { path.setLineDash(dash, count: dash.count, phase: 0) }
        color.setStroke()
        path.stroke()
    }

    func line(_ from: CGPoint, _ to: CGPoint, color: UIColor = DemoPageCanvas.rule, width: CGFloat = 1.5, dash: [CGFloat] = []) {
        let path = UIBezierPath()
        path.move(to: from)
        path.addLine(to: to)
        path.lineWidth = width
        if !dash.isEmpty { path.setLineDash(dash, count: dash.count, phase: 0) }
        color.setStroke()
        path.stroke()
    }

    func circle(center: CGPoint, radius: CGFloat, fill color: UIColor) {
        color.setFill()
        UIBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
    }

    /// A 1D barcode of random bar widths filling `rect`.
    func barcode(in rect: CGRect, seed: UInt64, color: UIColor = DemoPageCanvas.ink) {
        var random = DemoRandom(seed: seed)
        var x = rect.minX
        var isBar = true
        color.setFill()
        while x < rect.maxX {
            let width = CGFloat(random.next(in: 1...4)) * 2.2
            if isBar { UIRectFill(CGRect(x: x, y: rect.minY, width: min(width, rect.maxX - x), height: rect.height)) }
            x += width
            isBar.toggle()
        }
    }

    /// A QR-like 2D code: random modules plus three finder squares.
    func matrixCode(in rect: CGRect, seed: UInt64, modules: Int = 25) {
        var random = DemoRandom(seed: seed)
        let cell = rect.width / CGFloat(modules)
        Self.ink.setFill()
        func isFinder(_ row: Int, _ column: Int) -> Bool {
            (row < 8 && column < 8) || (row < 8 && column >= modules - 8) || (row >= modules - 8 && column < 8)
        }
        for row in 0..<modules {
            for column in 0..<modules where !isFinder(row, column) && random.next() % 2 == 0 {
                UIRectFill(CGRect(x: rect.minX + CGFloat(column) * cell, y: rect.minY + CGFloat(row) * cell, width: cell, height: cell))
            }
        }
        for (row, column) in [(0, 0), (0, modules - 7), (modules - 7, 0)] {
            let origin = CGPoint(x: rect.minX + CGFloat(column) * cell, y: rect.minY + CGFloat(row) * cell)
            fill(CGRect(x: origin.x, y: origin.y, width: cell * 7, height: cell * 7), Self.ink)
            fill(CGRect(x: origin.x + cell, y: origin.y + cell, width: cell * 5, height: cell * 5), .white)
            fill(CGRect(x: origin.x + cell * 2, y: origin.y + cell * 2, width: cell * 3, height: cell * 3), Self.ink)
        }
    }

    /// A handwritten signature (see `DemoSignature`) in ink.
    func signature(in rect: CGRect, variant: Int, color: UIColor = DemoPageCanvas.blueInk, width: CGFloat = 3.2) {
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(width)
        context.setStrokeColor(color.cgColor)
        for stroke in DemoSignature.strokes(in: rect, variant: variant) {
            guard let first = stroke.first else { continue }
            context.beginPath()
            context.move(to: first)
            for point in stroke.dropFirst() { context.addLine(to: point) }
            context.strokePath()
        }
        context.restoreGState()
    }

    /// A round rubber stamp: text around the ring and a bold word in the middle, slightly rotated.
    func roundStamp(center: CGPoint, radius: CGFloat, ring: String, middle: String, detail: String, color: UIColor, angle: CGFloat) {
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: angle)
        context.setAlpha(0.82)
        let outer = UIBezierPath(ovalIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
        outer.lineWidth = 5
        color.setStroke()
        outer.stroke()
        let innerRadius = radius - 44
        let inner = UIBezierPath(ovalIn: CGRect(x: -innerRadius, y: -innerRadius, width: innerRadius * 2, height: innerRadius * 2))
        inner.lineWidth = 2.5
        inner.stroke()
        let attributes = textAttributes(size: 21, weight: .bold, face: .sans, color: color, kern: 0)
        let characters = Array(ring)
        let spread = CGFloat.pi * 1.55
        for (index, character) in characters.enumerated() {
            let fraction = characters.count > 1 ? CGFloat(index) / CGFloat(characters.count - 1) : 0.5
            context.saveGState()
            context.rotate(by: -spread / 2 + spread * fraction)
            let glyph = String(character) as NSString
            let glyphSize = glyph.size(withAttributes: attributes)
            glyph.draw(at: CGPoint(x: -glyphSize.width / 2, y: -radius + 9), withAttributes: attributes)
            context.restoreGState()
        }
        text(middle, x: 0, y: -24, size: 34, weight: .heavy, color: color, align: .center, recognized: false)
        text(detail, x: 0, y: 16, size: 19, weight: .semibold, color: color, align: .center, recognized: false)
        context.restoreGState()
    }

    /// A rectangular stamp (e.g. a doctor's), slightly rotated.
    func boxStamp(center: CGPoint, lines stampLines: [String], color: UIColor, angle: CGFloat) {
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: angle)
        context.setAlpha(0.8)
        let lineHeight: CGFloat = 30
        let height = CGFloat(stampLines.count) * lineHeight + 26
        let width: CGFloat = 400
        stroke(CGRect(x: -width / 2, y: -height / 2, width: width, height: height), color, width: 3.5, radius: 6)
        for (index, string) in stampLines.enumerated() {
            text(string, x: 0, y: -height / 2 + 13 + CGFloat(index) * lineHeight, size: index == 0 ? 22 : 18, weight: index == 0 ? .bold : .semibold, color: color, align: .center, recognized: false)
        }
        context.restoreGState()
    }

    // MARK: Private

    private func textAttributes(size: CGFloat, weight: UIFont.Weight, face: Face, color: UIColor, kern: CGFloat) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.font: font(face, size, weight), .foregroundColor: color]
        if kern != 0 { attributes[.kern] = kern }
        return attributes
    }

    /// Stores the line with a normalised, bottom-left-origin box (Vision's convention).
    private func record(_ string: String, in rect: CGRect) {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let box = CGRect(
            x: rect.minX / size.width,
            y: 1 - rect.maxY / size.height,
            width: rect.width / size.width,
            height: rect.height / size.height
        )
        lines.append(OCRLine(text: trimmed, boundingBox: box, confidence: 1))
    }
}

#endif

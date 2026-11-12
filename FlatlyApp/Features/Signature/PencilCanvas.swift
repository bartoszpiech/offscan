import SwiftUI
import UIKit
import PencilKit

/// `PKCanvasView` wrapper: a pen in the chosen `SignatureInk` on white paper, finger and Pencil
/// input. Changing `ink` recolours the strokes already drawn (the delegate then updates the
/// binding, as for Clear); changing `clearToken` clears the canvas.
struct PencilCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var clearToken: Int
    var ink: SignatureInk

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.tool = ink.tool
        canvas.backgroundColor = .white
        canvas.isOpaque = true
        // PencilKit inverts ink in dark mode; the paper is always white, so keep the light look.
        canvas.overrideUserInterfaceStyle = .light
        canvas.isScrollEnabled = false
        canvas.drawing = drawing
        canvas.delegate = context.coordinator
        canvas.accessibilityLabel = String(localized: "Signature drawing area")
        canvas.accessibilityIdentifier = "signature.canvas"
        context.coordinator.lastClearToken = clearToken
        context.coordinator.lastInk = ink
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.drawing = $drawing
        if context.coordinator.lastClearToken != clearToken {
            context.coordinator.lastClearToken = clearToken
            canvas.drawing = PKDrawing()
        }
        if context.coordinator.lastInk != ink {
            context.coordinator.lastInk = ink
            canvas.tool = ink.tool
            if !canvas.drawing.strokes.isEmpty {
                canvas.drawing = ink.applied(to: canvas.drawing)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing)
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var drawing: Binding<PKDrawing>
        var lastClearToken = 0
        var lastInk: SignatureInk?

        init(drawing: Binding<PKDrawing>) {
            self.drawing = drawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing.wrappedValue = canvasView.drawing
        }
    }
}

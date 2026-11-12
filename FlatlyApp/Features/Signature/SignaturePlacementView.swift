import SwiftUI
import CoreGraphics
import PencilKit
import FlatlyCore

/// Shows the page (rendered without any existing signature) with the signature overlaid.
/// Drag to move, pinch or drag the corner handle to resize (aspect ratio of the drawing is kept).
/// "Place" reports a `SignaturePlacement` whose frame is normalised (top-left origin) relative to
/// the processed (rotated & cropped) page image. The signature starts near the bottom right,
/// moved off any recognised text (`SignatureSpotFinder`); the hint below the page wraps instead of
/// being truncated in a toolbar.
struct SignaturePlacementView: View {
    let pageID: UUID
    let recipe: PageRenderRecipe
    let drawingData: Data
    let onPlace: (SignaturePlacement) -> Void

    @Environment(AppServices.self) private var services
    @State private var pageImage: CGImage?
    @State private var signatureImage: CGImage?
    @State private var geometry = SignatureFrameGeometry(pageAspect: 1, drawingAspect: 3)
    @State private var frame: CGRect = .zero
    @State private var dragStart: CGRect?
    @State private var loadError: String?
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        Group {
            if let pageImage, let signatureImage {
                editor(page: pageImage, signature: signatureImage)
            } else if let loadError {
                ContentUnavailableView {
                    Label("Couldn't Prepare the Signature", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                }
            } else {
                ProgressView("Preparing…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Before the background, so the grouped background also covers the hint.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if pageImage != nil, signatureImage != nil {
                Text("Drag to move. Pinch or drag the handle to resize.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("signature.hint")
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(Text("Place Signature"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Place") {
                    onPlace(SignaturePlacement(drawingData: drawingData, frame: geometry.clamped(frame)))
                }
                .disabled(signatureImage == nil)
                .accessibilityIdentifier("signature.placeButton")
            }
        }
        .task { await load() }
    }

    // MARK: Editor

    private func editor(page: CGImage, signature: CGImage) -> some View {
        GeometryReader { geo in
            let container = CGRect(origin: .zero, size: geo.size).insetBy(dx: 16, dy: 16)
            let fitted = CropGeometry.fittedRect(imageSize: CGSize(width: page.width, height: page.height), in: container)
            let current = pinch == 1 ? frame : geometry.scaled(frame, by: pinch)
            let sigRect = CGRect(x: fitted.minX + current.minX * fitted.width,
                                 y: fitted.minY + current.minY * fitted.height,
                                 width: current.width * fitted.width,
                                 height: current.height * fitted.height)
            ZStack(alignment: .topLeading) {
                Image(decorative: page, scale: 1)
                    .resizable()
                    .frame(width: fitted.width, height: fitted.height)
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    .position(x: fitted.midX, y: fitted.midY)
                    .accessibilityHidden(true)

                Image(decorative: signature, scale: 1)
                    .resizable()
                    .frame(width: sigRect.width, height: sigRect.height)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    }
                    .contentShape(Rectangle())
                    .position(x: sigRect.midX, y: sigRect.midY)
                    .gesture(moveGesture(fitted: fitted))
                    .accessibilityElement()
                    .accessibilityLabel(Text("Signature"))
                    .accessibilityValue(Text(accessibilityPosition))
                    .accessibilityAddTraits(.allowsDirectInteraction)
                    .accessibilityAction(named: Text("Move Left")) { nudge(dx: -0.05, dy: 0) }
                    .accessibilityAction(named: Text("Move Right")) { nudge(dx: 0.05, dy: 0) }
                    .accessibilityAction(named: Text("Move Up")) { nudge(dx: 0, dy: -0.05) }
                    .accessibilityAction(named: Text("Move Down")) { nudge(dx: 0, dy: 0.05) }
                    .accessibilityAction(named: Text("Make Larger")) { frame = geometry.scaled(frame, by: 1.2) }
                    .accessibilityAction(named: Text("Make Smaller")) { frame = geometry.scaled(frame, by: 1 / 1.2) }
                    .accessibilityIdentifier("signature.overlay")

                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 24, height: 24)
                    .overlay {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.onAccent)
                    }
                    .shadow(radius: 2)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .position(x: sigRect.maxX, y: sigRect.maxY)
                    .gesture(resizeGesture(fitted: fitted))
                    .accessibilityElement()
                    .accessibilityLabel(Text("Resize signature"))
                    .accessibilityValue(Text(accessibilityPosition))
                    .accessibilityAdjustableAction { direction in
                        frame = geometry.scaled(frame, by: direction == .increment ? 1.2 : 1 / 1.2)
                    }
                    .accessibilityIdentifier("signature.resizeHandle")
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in frame = geometry.scaled(frame, by: value.magnification) }
            )
        }
    }

    private func moveGesture(fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = dragStart ?? frame
                if dragStart == nil { dragStart = frame }
                frame = geometry.moved(start, by: normalised(value.translation, in: fitted))
            }
            .onEnded { _ in dragStart = nil }
    }

    private func resizeGesture(fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = dragStart ?? frame
                if dragStart == nil { dragStart = frame }
                let d = normalised(value.translation, in: fitted)
                // Follow whichever axis the finger moved more (in width terms).
                let widthFromHeight = d.height * start.width / max(start.height, 0.0001)
                let delta = abs(d.width) >= abs(widthFromHeight) ? d.width : widthFromHeight
                frame = geometry.resized(start, toWidth: start.width + delta, anchor: .topLeft)
            }
            .onEnded { _ in dragStart = nil }
    }

    private func normalised(_ translation: CGSize, in fitted: CGRect) -> CGSize {
        guard fitted.width > 0, fitted.height > 0 else { return .zero }
        return CGSize(width: translation.width / fitted.width, height: translation.height / fitted.height)
    }

    private func nudge(dx: CGFloat, dy: CGFloat) {
        frame = geometry.moved(frame, by: CGSize(width: dx, height: dy))
    }

    private var accessibilityPosition: String {
        let pct = { (v: CGFloat) in Int((v * 100).rounded()) }
        return String(localized: "\(pct(frame.midX)) percent from the left, \(pct(frame.midY)) percent from the top, \(pct(frame.width)) percent of the page width", comment: "Signature position for VoiceOver")
    }

    // MARK: Loading

    private func load() async {
        guard pageImage == nil else { return }
        var base = recipe
        base.signature = nil
        let id = pageID
        let data = drawingData
        let processor = services.processor
        do {
            let bounds = try PKDrawing(data: data).bounds
            let drawingAspect = (bounds.width > 1 && bounds.height > 1) ? bounds.width / bounds.height : 3
            let longest: CGFloat = 1000
            let renderSize = drawingAspect >= 1
                ? CGSize(width: longest, height: max(1, (longest / drawingAspect).rounded()))
                : CGSize(width: max(1, (longest * drawingAspect).rounded()), height: longest)

            let page = try await processor.preview(pageID: id, recipe: base, maxDimension: 1600)
            let signature = try await Task.detached(priority: .userInitiated) {
                try SignatureRenderer().render(drawingData: data, size: renderSize)
            }.value

            let geo = SignatureFrameGeometry(pageAspect: CGFloat(page.width) / CGFloat(max(page.height, 1)), drawingAspect: drawingAspect)
            geometry = geo
            // OCR ran on the processed page, the same geometry as the placement frame. The model is
            // read here (main actor); decoding its OCR JSON (as `ScanPage.ocr` does) and the
            // candidate search run off it like the other core services.
            let ocrData = services.store.page(id: id)?.ocrData
            let preferred = geo.initialFrame
            frame = await Task.detached(priority: .userInitiated) {
                let lines = ocrData.flatMap { try? JSONDecoder().decode(OCRResult.self, from: $0) }?.lines ?? []
                return SignatureSpotFinder().frame(near: preferred, avoiding: lines)
            }.value
            pageImage = page
            signatureImage = signature
        } catch {
            loadError = error.localizedDescription
        }
    }
}

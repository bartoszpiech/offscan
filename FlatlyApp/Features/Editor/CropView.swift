import SwiftUI
import CoreGraphics

/// Rectangular crop editor. Shows `image` with a draggable crop rectangle (move by dragging the
/// inside, resize with the 8 edge/corner handles). The rect is normalised with a top-left origin
/// relative to `image`. `onConfirm(nil)` means "no crop". Always dark (white title and status bar on
/// the black canvas); an instruction line and Reset sit below the image.
struct CropView: View {
    let image: CGImage
    let onConfirm: (CGRect?) -> Void
    let onCancel: () -> Void

    @State private var rect: CGRect
    @State private var dragStartRect: CGRect?

    init(image: CGImage, cropRect: CGRect?, onConfirm: @escaping (CGRect?) -> Void, onCancel: @escaping () -> Void) {
        self.image = image
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _rect = State(initialValue: CropGeometry.clamped(cropRect ?? CropGeometry.fullRect))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let container = CGRect(origin: .zero, size: geo.size).insetBy(dx: 24, dy: 24)
                let fitted = CropGeometry.fittedRect(imageSize: CGSize(width: image.width, height: image.height), in: container)
                let cropFrame = frame(for: rect, in: fitted)
                ZStack(alignment: .topLeading) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .frame(width: fitted.width, height: fitted.height)
                        .position(x: fitted.midX, y: fitted.midY)
                        .accessibilityHidden(true)

                    CropDimmingShape(outer: fitted, inner: cropFrame)
                        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                        .allowsHitTesting(false)

                    Rectangle()
                        .strokeBorder(Color.white, lineWidth: 2)
                        .background(Color.white.opacity(0.001))
                        .overlay { gridLines }
                        .frame(width: cropFrame.width, height: cropFrame.height)
                        .position(x: cropFrame.midX, y: cropFrame.midY)
                        .gesture(moveGesture(fitted: fitted))
                        .accessibilityElement()
                        .accessibilityLabel(Text("Crop area"))
                        .accessibilityValue(Text(areaAccessibilityValue))
                        .accessibilityAction(named: Text("Move Left")) { move(dx: -0.02, dy: 0) }
                        .accessibilityAction(named: Text("Move Right")) { move(dx: 0.02, dy: 0) }
                        // Top-left origin: up is a negative dy.
                        .accessibilityAction(named: Text("Move Up")) { move(dx: 0, dy: -0.02) }
                        .accessibilityAction(named: Text("Move Down")) { move(dx: 0, dy: 0.02) }
                        .accessibilityIdentifier("crop.area")

                    ForEach(CropHandle.allCases) { handle in
                        let point = handle.point(in: cropFrame)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 20, height: 20)
                            .shadow(radius: 2)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .position(point)
                            .gesture(resizeGesture(handle, fitted: fitted))
                            .accessibilityElement()
                            .accessibilityLabel(handle.accessibilityLabel)
                            .accessibilityHint(Text("Swipe up or down to move this edge outward or inward."))
                            // Spoken after each swipe; stops changing at the minimum size or border.
                            .accessibilityValue(Text(accessibilityValue))
                            .accessibilityAdjustableAction { direction in
                                adjust(handle, outward: direction == .increment)
                            }
                            .accessibilityIdentifier("crop.handle.\(handle.rawValue)")
                    }
                }
            }
            .background(Color.black.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 4) {
                    // Tells this tool apart from Adjust Edges, whose handles look alike.
                    Text("Drag the frame or its handles to keep only part of the page.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        // Same cap as the editor's tool bar, so accessibility sizes can't eat the image.
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .accessibilityIdentifier("crop.instruction")
                    Button {
                        withAnimation { rect = CropGeometry.fullRect }
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .labelStyle(.toolbarCaption)
                    // Keeps the tappable area to the button, not the whole bottom strip.
                    .frame(maxWidth: 160)
                    .disabled(CropGeometry.isFull(rect))
                    .accessibilityIdentifier("crop.resetButton")
                }
                .padding(.vertical, 4)
            }
            .navigationTitle(Text("Crop"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .accessibilityIdentifier("crop.cancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onConfirm(CropGeometry.isFull(rect) ? nil : rect)
                    }
                    .accessibilityIdentifier("crop.doneButton")
                }
            }
        }
        // Black canvas: white title and status bar, dark glass.
        .preferredColorScheme(.dark)
    }

    // MARK: Geometry

    private func frame(for rect: CGRect, in fitted: CGRect) -> CGRect {
        CGRect(x: fitted.minX + rect.minX * fitted.width,
               y: fitted.minY + rect.minY * fitted.height,
               width: rect.width * fitted.width,
               height: rect.height * fitted.height)
    }

    private func normalisedDelta(_ translation: CGSize, fitted: CGRect) -> CGSize {
        guard fitted.width > 0, fitted.height > 0 else { return .zero }
        return CGSize(width: translation.width / fitted.width, height: translation.height / fitted.height)
    }

    private func moveGesture(fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = dragStartRect ?? rect
                if dragStartRect == nil { dragStartRect = rect }
                let d = normalisedDelta(value.translation, fitted: fitted)
                rect = Self.moved(start, dx: d.width, dy: d.height)
            }
            .onEnded { _ in dragStartRect = nil }
    }

    private func resizeGesture(_ handle: CropHandle, fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = dragStartRect ?? rect
                if dragStartRect == nil { dragStartRect = rect }
                let d = normalisedDelta(value.translation, fitted: fitted)
                rect = handle.resize(start, by: d)
            }
            .onEnded { _ in dragStartRect = nil }
    }

    /// `rect` shifted by (dx, dy), kept inside the image.
    private static func moved(_ rect: CGRect, dx: CGFloat, dy: CGFloat) -> CGRect {
        var moved = rect
        moved.origin.x = min(max(rect.minX + dx, 0), 1 - rect.width)
        moved.origin.y = min(max(rect.minY + dy, 0), 1 - rect.height)
        return moved
    }

    /// VoiceOver "Move …" actions on the crop area.
    private func move(dx: CGFloat, dy: CGFloat) {
        rect = Self.moved(rect, dx: dx, dy: dy)
    }

    private func adjust(_ handle: CropHandle, outward: Bool) {
        let step: CGFloat = outward ? 0.02 : -0.02
        let d = CGSize(width: handle.horizontalSign * step, height: handle.verticalSign * step)
        rect = handle.resize(rect, by: d)
    }

    private var accessibilityValue: String {
        let pct = { (v: CGFloat) in Int((v * 100).rounded()) }
        return String(localized: "\(pct(rect.width)) percent wide, \(pct(rect.height)) percent high", comment: "Crop area size for VoiceOver")
    }

    /// Size and position of the crop area, so a VoiceOver user can tell where a Move left it.
    private var areaAccessibilityValue: String {
        let pct = { (v: CGFloat) in Int((v * 100).rounded()) }
        let position = String(localized: "\(pct(rect.minX)) percent from left, \(pct(rect.minY)) percent from top")
        return accessibilityValue + ", " + position
    }

    private var gridLines: some View {
        GeometryReader { geo in
            Path { p in
                for i in 1...2 {
                    let x = geo.size.width * CGFloat(i) / 3
                    let y = geo.size.height * CGFloat(i) / 3
                    p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: geo.size.height))
                    p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

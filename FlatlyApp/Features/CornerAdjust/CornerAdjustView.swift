import SwiftUI
import CoreGraphics
import FlatlyCore

/// Full-screen editor showing `image` with four draggable corner handles (pre-filled from `quad`),
/// edge midpoint handles that move a whole edge, and a magnifier loupe while dragging. `quad` uses
/// FlatlyCore's normalised bottom-left-origin coordinates.
///
/// The view embeds its own `NavigationStack` (navigation bar: Cancel and Done; a one-line
/// instruction above a captioned bottom control row: Reset, Full Page and, in batch review,
/// "Use All"), so present it modally
/// (`.sheet` / `.fullScreenCover`) or as a whole screen — do not push it onto another navigation
/// stack. It always uses the dark appearance (white title and status bar on the black canvas,
/// bright accent outline); everything outside the outline is dimmed so the page keeps its colour.
/// Optional step indicator / hint banner: `.cornerAdjustCaption(step:hint:)`.
/// When `onConfirmAll` is set (batch review), "Use All" passes the current outline like Done and
/// lets the caller accept the remaining pages without review. When `onDiscard` is set (batch
/// review), the row starts with "Delete Page", which drops this page and shows the next one.
struct CornerAdjustView: View {
    let image: CGImage
    let initialQuad: Quadrilateral
    let onConfirm: (Quadrilateral) -> Void
    let onCancel: () -> Void
    let onConfirmAll: ((Quadrilateral) -> Void)?
    let onDiscard: (() -> Void)?

    @State private var quad: Quadrilateral
    @State private var drag: DragState?
    @Environment(\.cornerAdjustCaption) private var caption

    init(
        image: CGImage,
        quad: Quadrilateral,
        onConfirm: @escaping (Quadrilateral) -> Void,
        onCancel: @escaping () -> Void,
        onConfirmAll: ((Quadrilateral) -> Void)? = nil,
        onDiscard: (() -> Void)? = nil
    ) {
        self.image = image
        self.initialQuad = quad
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.onConfirmAll = onConfirmAll
        self.onDiscard = onDiscard
        _quad = State(initialValue: quad)
    }

    private struct DragState: Equatable {
        let handle: QuadHandle
        let startQuad: Quadrilateral
    }

    private static let canvasSpace = "cornerAdjust.canvas"
    /// Padding around the image so handles on the image border stay fully touchable.
    private static let canvasInset: CGFloat = 28
    /// Normalised step for VoiceOver nudge actions.
    private static let nudgeStep: CGFloat = 0.01

    var body: some View {
        NavigationStack {
            canvas
                .background(Color.black.ignoresSafeArea())
                .overlay(alignment: .top) { banners }
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomControls }
                .navigationTitle(Text("Adjust Edges"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .toolbarBackground(.visible, for: .navigationBar)
        }
        // Black canvas: white title and status bar, dark glass, the bright dark-mode accent.
        .preferredColorScheme(.dark)
        // Dragging the top handles must never swipe-dismiss a hosting sheet.
        .interactiveDismissDisabled()
        .sensoryFeedback(.selection, trigger: drag?.handle) { _, new in new != nil }
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { geo in
            let bounds = CGRect(origin: .zero, size: geo.size).insetBy(dx: Self.canvasInset, dy: Self.canvasInset)
            let fit = FittedImageRect(imageSize: CGSize(width: image.width, height: image.height), in: bounds)
            ZStack {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .frame(width: fit.rect.width, height: fit.rect.height)
                    .position(x: fit.rect.midX, y: fit.rect.midY)
                    .accessibilityHidden(true)

                QuadDimmingShape(quad: quad)
                    .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
                    .overlay(QuadOverlayShape(quad: quad).stroke(outlineColor, style: StrokeStyle(lineWidth: 2, lineJoin: .round)))
                    .frame(width: fit.rect.width, height: fit.rect.height)
                    .position(x: fit.rect.midX, y: fit.rect.midY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                ForEach(visibleEdges(in: fit), id: \.self) { edge in
                    handleView(.edge(edge), fit: fit)
                }
                ForEach(QuadCorner.allCases, id: \.self) { corner in
                    handleView(.corner(corner), fit: fit)
                }

                if let drag {
                    let normalised = drag.handle.point(in: quad)
                    MagnifierLoupe(image: image, displayedSize: fit.rect.size, focus: fit.localPoint(normalised), quad: quad)
                        .position(MagnifierLoupe.center(for: fit.viewPoint(normalised), in: geo.size))
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .coordinateSpace(.named(Self.canvasSpace))
            .animation(.easeOut(duration: 0.15), value: drag == nil)
        }
    }

    private func handleView(_ handle: QuadHandle, fit: FittedImageRect) -> some View {
        let point = handle.point(in: quad)
        return CornerHandle(style: handle.isCorner ? .corner : .edge, isActive: drag?.handle == handle, angle: edgeAngle(handle, fit: fit))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.canvasSpace))
                    .onChanged { value in
                        let start: Quadrilateral
                        if let drag, drag.handle == handle {
                            start = drag.startQuad
                        } else {
                            start = quad
                            drag = DragState(handle: handle, startQuad: quad)
                        }
                        quad = start.moving(handle, by: fit.normalisedDelta(value.translation))
                    }
                    .onEnded { _ in drag = nil }
            )
            .accessibilityElement()
            .accessibilityLabel(Text(handle.accessibilityLabel))
            .accessibilityValue(Text("\(percent(point.x)) percent from left, \(percent(1 - point.y)) percent from top"))
            .accessibilityHint(Text("Drag to adjust the document outline, or use the actions to move it."))
            .accessibilityIdentifier(handle.accessibilityIdentifier)
            .accessibilityActions {
                Button("Move up") { nudge(handle, dx: 0, dy: Self.nudgeStep) }
                Button("Move down") { nudge(handle, dx: 0, dy: -Self.nudgeStep) }
                Button("Move left") { nudge(handle, dx: -Self.nudgeStep, dy: 0) }
                Button("Move right") { nudge(handle, dx: Self.nudgeStep, dy: 0) }
            }
            .position(fit.viewPoint(point))
    }

    /// Edge handles are hidden when the edge is too short on screen to fit them between the corners.
    private func visibleEdges(in fit: FittedImageRect) -> [QuadEdge] {
        QuadEdge.allCases.filter { edge in
            // Never remove the handle being dragged, or its gesture would be cancelled mid-drag.
            if drag?.handle == .edge(edge) { return true }
            let (a, b) = edge.corners
            let p = fit.viewPoint(quad[a]), q = fit.viewPoint(quad[b])
            return hypot(q.x - p.x, q.y - p.y) > CornerHandle.hitSize * 2.5
        }
    }

    private func edgeAngle(_ handle: QuadHandle, fit: FittedImageRect) -> Angle {
        guard case .edge(let edge) = handle else { return .zero }
        let (a, b) = edge.corners
        let p = fit.viewPoint(quad[a]), q = fit.viewPoint(quad[b])
        return .radians(atan2(q.y - p.y, q.x - p.x))
    }

    private func nudge(_ handle: QuadHandle, dx: CGFloat, dy: CGFloat) {
        quad = quad.moving(handle, by: CGVector(dx: dx, dy: dy))
    }

    private func percent(_ value: CGFloat) -> Int { Int((value * 100).rounded()) }

    private var outlineColor: Color { quad.isConvex ? Color.accentColor : Color.red }

    // MARK: Banners

    private var banners: some View {
        VStack(spacing: 8) {
            if let hint = caption.hint {
                banner(Text(hint), systemImage: "viewfinder")
                    .accessibilityIdentifier("corner.hint")
            }
            if !quad.isConvex {
                banner(Text("The corners must form a convex shape."), systemImage: "exclamationmark.triangle.fill")
                    .accessibilityIdentifier("corner.invalidShape")
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.2), value: quad.isConvex)
    }

    private func banner(_ text: Text, systemImage: String) -> some View {
        Label { text } icon: { Image(systemName: systemImage) }
            .font(.footnote)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .transition(.opacity)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", action: onCancel)
                .accessibilityIdentifier("corner.cancel")
        }
        ToolbarItem(placement: .principal) {
            VStack(spacing: 0) {
                Text("Adjust Edges").font(.headline)
                if let step = caption.step {
                    Text(step).font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("corner.title")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { onConfirm(quad) }
                .disabled(!quad.isConvex)
                .accessibilityHint(Text("Uses the outlined area as the page."))
                .accessibilityIdentifier("corner.done")
        }
    }

    // MARK: Bottom controls

    /// A one-line instruction (always shown, also under the "No document detected" banner: this is
    /// the general how-to, the banner the warning), then captioned secondary controls, each taking
    /// an equal share of the width (like the page editor's tool bar). Bottom-bar toolbar items would
    /// render icon-only on iOS 26.
    private var bottomControls: some View {
        VStack(spacing: 4) {
            instruction
            controlRow
        }
        .padding(.vertical, 4)
    }

    /// Tells this tool apart from Crop, whose handles look alike.
    private var instruction: some View {
        Text("Drag the handles to the edges of the paper to straighten the page.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            // Same cap as the tool bar below, so accessibility sizes can't eat the canvas.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityIdentifier("corner.instruction")
    }

    private var controlRow: some View {
        HStack(spacing: 0) {
            if let onDiscard {
                Button(role: .destructive) {
                    onDiscard()
                } label: {
                    Label("Delete Page", systemImage: "trash")
                }
                .accessibilityHint(Text("Removes this page from the scan and shows the next one."))
                .accessibilityIdentifier("corner.deletePage")
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { quad = initialQuad }
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .disabled(quad == initialQuad)
            .accessibilityHint(Text("Restores the detected corners."))
            .accessibilityIdentifier("corner.reset")

            if let onConfirmAll {
                Button {
                    onConfirmAll(quad)
                } label: {
                    Label("Use All", systemImage: "checkmark.circle")
                }
                .fontWeight(.semibold)
                .disabled(!quad.isConvex)
                .accessibilityHint(Text("Uses this outline and the detected edges for every remaining page."))
                .accessibilityIdentifier("corner.useAll")
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { quad = .fullFrame }
            } label: {
                Label("Full Page", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .disabled(quad == .fullFrame)
            .accessibilityHint(Text("Uses the whole image."))
            .accessibilityIdentifier("corner.fullPage")
        }
        .labelStyle(.toolbarCaption)
        .padding(.horizontal, 8)
    }
}

private extension QuadHandle {
    var isCorner: Bool {
        if case .corner = self { return true }
        return false
    }
}

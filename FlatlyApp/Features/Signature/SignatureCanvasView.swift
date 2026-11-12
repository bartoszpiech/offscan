import SwiftUI
import PencilKit

/// Draw a signature (or reuse the saved one). A new drawing is saved for reuse in `UserDefaults`
/// under `"savedSignature"` (`PKDrawing.dataRepresentation()`) only while the "Save as My
/// Signature" / "Replace Saved Signature" toggle is on. The toggle starts on only when nothing is
/// saved yet, so a drawing for someone else, initials or a test scribble never silently replace
/// the saved signature. Meant to be shown inside a `NavigationStack` (see `SignatureFlowView`).
///
/// An "Ink Color" row under the canvas picks the pen colour (`SignatureInk`: blue by default, navy,
/// black), remembered under `"signatureInk"`; switching recolours what is already drawn, and Done
/// stores the drawing in one colour. "Use Saved Signature" keeps the saved drawing's own colour.
struct SignatureCanvasView: View {
    static let savedSignatureKey = "savedSignature"

    let onDone: (Data) -> Void
    let onCancel: () -> Void

    @AppStorage(SignatureCanvasView.savedSignatureKey) private var savedSignature: Data?
    @AppStorage(SignatureInk.storageKey) private var ink: SignatureInk = .blue
    @State private var drawing = SignatureCanvasView.initialDrawing
    @State private var clearToken = 0
    @State private var confirmForgetSaved = false
    /// Done stores the drawing as the saved signature.
    @State private var saveAsMine: Bool
    @ScaledMetric(relativeTo: .body) private var canvasHeight: CGFloat = 240
    @ScaledMetric(relativeTo: .body) private var swatchSize: CGFloat = 26

    /// Empty, except with the DEBUG demo library (`FLATLY_DEMO_DATA=1`), where the canvas starts
    /// with a sample signature so screenshots show it in use.
    private static var initialDrawing: PKDrawing {
        #if DEBUG
        if DemoLibrarySeeder.isEnabled {
            return DemoSignature.drawing(in: CGRect(x: 40, y: 30, width: 280, height: 130), color: SignatureInk.current.uiColor)
        }
        #endif
        return PKDrawing()
    }

    init(onDone: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
        self.onDone = onDone
        self.onCancel = onCancel
        // Set here, not in onAppear: that fires again when coming back from the placement screen
        // and would reset the user's choice. @AppStorage uses UserDefaults.standard.
        _saveAsMine = State(initialValue: UserDefaults.standard.data(forKey: Self.savedSignatureKey) == nil)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let savedSignature {
                    Button {
                        onDone(savedSignature)
                    } label: {
                        Label("Use Saved Signature", systemImage: "signature")
                            .onAccentForeground()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("signature.useSavedButton")

                    Text("Or draw a new one:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Sign in the box with your finger or Apple Pencil.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                PencilCanvas(drawing: $drawing, clearToken: clearToken, ink: ink)
                    .frame(height: min(max(canvasHeight, 200), 360))
                    .overlay(alignment: .bottom) {
                        // Signature baseline guide (on the always-white paper).
                        Rectangle()
                            .fill(Color.gray.opacity(0.35))
                            .frame(height: 1)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 48)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color(.separator), lineWidth: 1)
                            .allowsHitTesting(false)
                    }

                inkRow

                HStack {
                    Button(role: .destructive) {
                        clearToken += 1
                        drawing = PKDrawing()
                    } label: {
                        Label("Clear", systemImage: "eraser")
                    }
                    .disabled(drawing.strokes.isEmpty)
                    .accessibilityIdentifier("signature.clearButton")

                    Spacer()

                    if savedSignature != nil {
                        Button(role: .destructive) {
                            confirmForgetSaved = true
                        } label: {
                            Label("Forget Saved Signature", systemImage: "trash")
                        }
                        .accessibilityIdentifier("signature.forgetSavedButton")
                    }
                }
                .buttonStyle(.bordered)

                saveToggle
            }
            .padding()
        }
        // The sheet no longer bounces under vertical finger strokes when the content fits.
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(Text("Signature"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
                    .accessibilityIdentifier("signature.cancelButton")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    // One colour for the whole signature, whatever was drawn before a switch.
                    let data = ink.applied(to: drawing).dataRepresentation()
                    if saveAsMine { savedSignature = data }
                    onDone(data)
                }
                .disabled(drawing.strokes.isEmpty)
                .accessibilityIdentifier("signature.doneButton")
            }
        }
        .confirmationDialog(Text("Forget the saved signature?"), isPresented: $confirmForgetSaved, titleVisibility: .visible) {
            Button("Forget Signature", role: .destructive) {
                savedSignature = nil
                saveAsMine = true   // back to the fresh-sheet default
            }
        } message: {
            Text("Signatures already placed on pages are not affected.")
        }
    }

    /// "Ink Color" and a swatch per `SignatureInk`; the chosen one is ringed.
    private var inkRow: some View {
        HStack(spacing: 12) {
            Text("Ink Color")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            ForEach(SignatureInk.allCases) { option in
                inkSwatch(option)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func inkSwatch(_ option: SignatureInk) -> some View {
        let isSelected = option == ink
        let size = min(swatchSize, 40)
        return Button {
            ink = option
        } label: {
            Circle()
                .fill(option.color)
                .frame(width: size, height: size)
                // Keeps the navy and black swatches visible on the dark grouped background.
                .overlay(Circle().strokeBorder(Color(.separator), lineWidth: 1))
                .padding(4)
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(Color.primary, lineWidth: 2)
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(option.name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("signature.ink.\(option.rawValue)")
    }

    /// Inset-grouped row with the save switch (and, before anything is saved, why to keep it on).
    private var saveToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                // Two literals, so both keys are extracted.
                if savedSignature == nil {
                    Toggle("Save as My Signature", isOn: $saveAsMine)
                } else {
                    Toggle("Replace Saved Signature", isOn: $saveAsMine)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityIdentifier("signature.saveAsMineToggle")

            if savedSignature == nil {
                Text("Next time you can sign with one tap.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

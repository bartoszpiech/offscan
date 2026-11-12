import SwiftUI
import PhotosUI

/// Inline Photos picker (up to 20 images, ordered) with our own Cancel / Add buttons, so the
/// import flow knows deterministically when the user has finished choosing.
struct PhotoSelectionView: View {
    @Binding var selection: [PhotosPickerItem]
    let onCancel: () -> Void
    let onAdd: () -> Void

    static let maxSelectionCount = 20

    var body: some View {
        NavigationStack {
            PhotosPicker(
                selection: $selection,
                maxSelectionCount: Self.maxSelectionCount,
                selectionBehavior: .continuousAndOrdered,
                matching: .images,
                preferredItemEncoding: .current
            ) {
                Text("Select Photos")
            }
            .photosPickerStyle(.inline)
            .photosPickerDisabledCapabilities(.selectionActions)
            .ignoresSafeArea(edges: .bottom)
            .accessibilityIdentifier("import.photoPicker")
            .navigationTitle(Text("Select Photos"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .accessibilityIdentifier("import.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: onAdd) {
                        if selection.isEmpty {
                            Text("Add")
                        } else {
                            Text("Add (\(selection.count))")
                        }
                    }
                    .disabled(selection.isEmpty)
                    .accessibilityIdentifier("import.add")
                }
            }
        }
    }
}

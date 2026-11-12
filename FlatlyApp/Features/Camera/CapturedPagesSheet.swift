import SwiftUI

/// The pages taken so far in a Offscan camera session, opened from the camera's thumbnail over the
/// live camera (auto-capture is paused meanwhile). Each page can be deleted (button or swipe);
/// "Keep Scanning" closes the sheet; "Finish Scanning" closes it and ends shooting like the
/// camera's Done.
struct CapturedPagesSheet: View {
    let pages: CameraPageQueue
    /// Same condition as the camera's Done (at least one page, no photo still on its way).
    let canFinish: Bool
    let onDelete: (UUID) -> Void
    /// Finish Scanning: the camera closes this sheet, then ends shooting.
    let onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(pages.shots.enumerated()), id: \.element.id) { index, shot in
                    row(shot, number: index + 1)
                }
            }
            // The primary action, full width at the bottom; Keep Scanning stays the secondary one
            // in the bar.
            .safeAreaInset(edge: .bottom) {
                Button(action: onFinish) {
                    Text("Finish Scanning")
                        .font(.headline)
                        .onAccentForeground()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canFinish)
                .accessibilityIdentifier("camera.pages.finish")
                .padding(.horizontal)
                .padding(.vertical, 8)
                // Matches the sheet, so rows scrolling under the button stay hidden.
                .background(Color(uiColor: .systemGroupedBackground))
            }
            .navigationTitle(Text("Scanned Pages"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Keep Scanning") { dismiss() }
                        .accessibilityIdentifier("camera.pages.keepScanning")
                }
            }
        }
    }

    private func row(_ shot: CameraPageQueue.Shot, number: Int) -> some View {
        HStack(spacing: 12) {
            thumbnail(shot)
            Text("Page \(number)")
            Spacer()
            Button(role: .destructive) {
                onDelete(shot.id)
            } label: {
                Image(systemName: "trash")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Delete Page"))
            .accessibilityIdentifier("camera.pages.delete")
        }
        .swipeActions {
            Button(role: .destructive) {
                onDelete(shot.id)
            } label: {
                Label("Delete Page", systemImage: "trash")
            }
        }
    }

    private func thumbnail(_ shot: CameraPageQueue.Shot) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return ZStack {
            Color(.secondarySystemBackground)
            if let image = shot.thumbnail {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
            } else if shot.isStaging {
                ProgressView()
            } else {
                Image(systemName: "doc")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}

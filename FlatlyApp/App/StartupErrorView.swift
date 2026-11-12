import SwiftUI
import UIKit

/// Shown instead of the library when it can't be opened at launch (e.g. the device is out of
/// storage while the database recovers), so the app explains the problem instead of crashing.
/// It first reassures (the documents are still on the device), then says how to free space on
/// this kind of device (iPhone / iPad Storage) and not to delete the app. "Try Again" re-opens the
/// library; the technical details (error domain and code, for support) are shown only on demand.
/// The content scrolls at large text sizes and stays centred otherwise. It shows no document data,
/// so it needs no app lock.
struct StartupErrorView: View {
    /// Localized description of the failure plus its error domain and code, shown in small print
    /// (selectable, for support) after "Show Details".
    let details: String?
    let retry: () -> Void

    @State private var showsDetails = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                ContentUnavailableView {
                    Label("Can't Open Your Library", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    VStack(spacing: 12) {
                        Text("Your documents haven't been deleted. They're still on this device.")
                            .foregroundStyle(.primary)
                        storageHint
                    }
                } actions: {
                    actions
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// Where to free space, named as in this device's Settings (separate literal keys, so both are
    /// localized).
    @ViewBuilder
    private var storageHint: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            Text("Offscan couldn't open them, usually because the device is almost out of storage. Free up some space (Settings > General > iPad Storage), then tap Try Again. Don't delete Offscan to make room: that would delete your documents too.")
        } else {
            Text("Offscan couldn't open them, usually because the device is almost out of storage. Free up some space (Settings > General > iPhone Storage), then tap Try Again. Don't delete Offscan to make room: that would delete your documents too.")
        }
    }

    @ViewBuilder
    private var actions: some View {
        Button {
            retry()
        } label: {
            Text("Try Again")
                .onAccentForeground()
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("startupError.retry")
        if details != nil {
            Button {
                withAnimation { showsDetails.toggle() }
            } label: {
                if showsDetails {
                    Text("Hide Details")
                } else {
                    Text("Show Details")
                }
            }
            .buttonStyle(.borderless)
            .font(.footnote)
            .accessibilityIdentifier("startupError.showDetails")
        }
        if showsDetails, let details {
            Text(verbatim: details)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(6)
                .textSelection(.enabled)
                .accessibilityIdentifier("startupError.details")
        }
    }
}

#if DEBUG
struct StartupErrorView_Previews: PreviewProvider {
    static var previews: some View {
        StartupErrorView(details: "The file couldn't be saved because there isn't enough space. (NSCocoaErrorDomain 640)", retry: {})
    }
}
#endif

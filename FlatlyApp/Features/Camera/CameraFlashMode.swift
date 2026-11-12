import AVFoundation
import SwiftUI

/// Flash setting of Offscan's camera, cycled by the top-bar button: auto → on → off.
enum CameraFlashMode: String, CaseIterable, Sendable {
    case auto, on, off

    var next: CameraFlashMode {
        switch self {
        case .auto: .on
        case .on: .off
        case .off: .auto
        }
    }

    var captureMode: AVCaptureDevice.FlashMode {
        switch self {
        case .auto: .auto
        case .on: .on
        case .off: .off
        }
    }

    var systemImage: String {
        switch self {
        case .auto: "bolt.badge.automatic.fill"
        case .on: "bolt.fill"
        case .off: "bolt.slash.fill"
        }
    }

    /// Spoken value of the flash button.
    var accessibilityValue: String {
        switch self {
        case .auto: String(localized: "Automatic")
        case .on: String(localized: "On")
        case .off: String(localized: "Off")
        }
    }
}

import AVFoundation
import Foundation

/// Why the camera is paused while the camera screen is open (the session was interrupted, or
/// stopped after a runtime error). The shutter and auto-capture are off meanwhile.
enum CameraInterruption: Equatable, Sendable {
    case background, multitasking, inUseByAnotherApp, systemPressure, other
    /// The session stopped after a runtime error and an automatic restart didn't help.
    case failed

    init(reason: AVCaptureSession.InterruptionReason?) {
        switch reason {
        case .videoDeviceNotAvailableInBackground?: self = .background
        case .videoDeviceInUseByAnotherClient?: self = .inUseByAnotherApp
        case .videoDeviceNotAvailableWithMultipleForegroundApps?: self = .multitasking
        case .videoDeviceNotAvailableDueToSystemPressure?: self = .systemPressure
        default: self = .other   // nil, audio, and reasons added in later SDKs
        }
    }

    /// Shown in the camera's hint capsule; nil for `.background` (the screen isn't visible then).
    var message: String? {
        switch self {
        case .background: nil
        case .multitasking: String(localized: "Make Offscan full screen to use the camera")
        case .inUseByAnotherApp: String(localized: "The camera is being used by another app")
        case .systemPressure: String(localized: "The camera is paused while your device cools down")
        case .other: String(localized: "The camera is paused")
        case .failed: String(localized: "The camera stopped working")
        }
    }
}

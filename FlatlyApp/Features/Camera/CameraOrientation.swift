import CoreGraphics
import ImageIO
import UIKit

/// The interface orientation the camera screen is shown in, and what it means for the back
/// camera's landscape sensor: how far the preview and photos are rotated, and how Vision must
/// rotate a raw video frame to make it upright.
///
/// The camera follows the *interface* orientation (not the physical device orientation) so the
/// photo, the live outline and the preview always agree, also with rotation lock on.
enum CameraOrientation: Sendable, Equatable {
    case portrait, portraitUpsideDown, landscapeLeft, landscapeRight

    init(_ interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        default: self = .portrait
        }
    }

    /// `AVCaptureConnection.videoRotationAngle` (degrees clockwise) that makes the back camera's
    /// output upright. The sensor's native orientation is landscape with the Home side on the
    /// right, i.e. `.landscapeRight` = 0°.
    var rotationAngle: CGFloat {
        switch self {
        case .portrait: 90
        case .landscapeRight: 0
        case .portraitUpsideDown: 270
        case .landscapeLeft: 180
        }
    }

    /// Orientation passed to Vision for an unrotated video frame (same rotation as `rotationAngle`).
    var visionOrientation: CGImagePropertyOrientation {
        switch self {
        case .portrait: .right
        case .landscapeRight: .up
        case .portraitUpsideDown: .left
        case .landscapeLeft: .down
        }
    }

    /// Whether the upright image is taller than wide (the sensor is landscape).
    var isPortrait: Bool {
        self == .portrait || self == .portraitUpsideDown
    }

    /// Size of the upright image for a sensor-oriented buffer of `sensorSize`.
    func uprightSize(forSensorSize sensorSize: CGSize) -> CGSize {
        isPortrait ? CGSize(width: sensorSize.height, height: sensorSize.width) : sensorSize
    }
}

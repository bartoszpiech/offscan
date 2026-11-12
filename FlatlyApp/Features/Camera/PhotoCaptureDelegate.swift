import AVFoundation

/// Delegate for a single `capturePhoto` call. Hands the encoded photo (HEIC/JPEG, with EXIF
/// orientation) to `completion` exactly once.
///
/// AVFoundation calls all of one capture's delegate methods serially on its own queue, so the
/// mutable state below is never accessed concurrently. The object is created and retained on the
/// session queue (`CaptureSessionPipeline.inProgressCaptures`) until `onFinished` runs.
final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: @Sendable (Result<Data, Error>) -> Void
    private let onFinished: @Sendable () -> Void
    private var didComplete = false

    init(completion: @escaping @Sendable (Result<Data, Error>) -> Void, onFinished: @escaping @Sendable () -> Void) {
        self.completion = completion
        self.onFinished = onFinished
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            complete(.failure(error))
        } else if let data = photo.fileDataRepresentation() {
            complete(.success(data))
        } else {
            complete(.failure(CameraError.noPhotoData))
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        complete(.failure(error ?? CameraError.noPhotoData))
        onFinished()
    }

    private func complete(_ result: Result<Data, Error>) {
        guard !didComplete else { return }
        didComplete = true
        completion(result)
    }
}

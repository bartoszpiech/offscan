import Foundation

/// An alert shown at the end of a scan/import flow. `result` is what the flow reports to its
/// `onFinished` callback once the alert is dismissed.
struct CaptureAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let result: ScanDocument?
}

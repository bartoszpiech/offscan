import SwiftUI

/// Optional context shown by `CornerAdjustView`: a step indicator (e.g. "Page 2 of 3") under the
/// title and a hint banner (e.g. "No document detected…"). Set with `.cornerAdjustCaption(step:hint:)`.
struct CornerAdjustCaption: Equatable, Sendable {
    var step: String?
    var hint: String?
}

private struct CornerAdjustCaptionKey: EnvironmentKey {
    static let defaultValue = CornerAdjustCaption()
}

extension EnvironmentValues {
    var cornerAdjustCaption: CornerAdjustCaption {
        get { self[CornerAdjustCaptionKey.self] }
        set { self[CornerAdjustCaptionKey.self] = newValue }
    }
}

extension View {
    /// Supplies a step indicator and/or hint banner to a `CornerAdjustView` below.
    func cornerAdjustCaption(step: String? = nil, hint: String? = nil) -> some View {
        environment(\.cornerAdjustCaption, CornerAdjustCaption(step: step, hint: hint))
    }
}

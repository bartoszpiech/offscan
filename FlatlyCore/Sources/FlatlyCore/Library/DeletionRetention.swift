import Foundation

/// How long a deleted document stays in Recently Deleted before it is erased for good. The app
/// stores when each document was deleted, lists it with `daysRemaining(deletedAt:now:)` and erases
/// it at launch once `isExpired(deletedAt:now:)`.
///
/// Days are 24-hour periods counted from the moment of deletion, so a time-zone or daylight-saving
/// change never shortens or extends the retention.
public struct DeletionRetention: Sendable, Equatable {
    /// 30 days, like Recently Deleted in Photos and Notes.
    public static let standard = DeletionRetention(days: 30)

    /// Number of days a deleted document is kept (at least 1).
    public let days: Int

    private static let secondsPerDay: TimeInterval = 86_400

    /// A retention of `days` days; values below 1 count as 1.
    public init(days: Int) {
        self.days = max(1, days)
    }

    /// When a document deleted at `deletedAt` is due to be erased.
    public func expiry(deletedAt: Date) -> Date {
        deletedAt.addingTimeInterval(TimeInterval(days) * Self.secondsPerDay)
    }

    /// Whether a document deleted at `deletedAt` is due to be erased at `now` (from the expiry on).
    public func isExpired(deletedAt: Date, now: Date) -> Bool {
        now >= expiry(deletedAt: deletedAt)
    }

    /// Whole days left before a document deleted at `deletedAt` is erased, rounded up, so the list
    /// shows "30 days left" right after deleting and "1 day left" during the last day. Clamped to
    /// `1...days`: an expired document that is still listed shows 1, and a `deletedAt` in the
    /// future (the clock was set back) shows `days`.
    public func daysRemaining(deletedAt: Date, now: Date) -> Int {
        let seconds = expiry(deletedAt: deletedAt).timeIntervalSince(now)
        let remaining = Int((seconds / Self.secondsPerDay).rounded(.up))
        return min(max(remaining, 1), days)
    }
}

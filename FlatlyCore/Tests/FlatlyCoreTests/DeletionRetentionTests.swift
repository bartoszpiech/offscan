import Foundation
import Testing
@testable import FlatlyCore

struct DeletionRetentionTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let day: TimeInterval = 86_400
    private let retention = DeletionRetention.standard

    private func deleted(daysAgo days: Double) -> Date {
        now.addingTimeInterval(-days * day)
    }

    @Test func standardKeepsThirtyDays() {
        #expect(retention.days == 30)
        #expect(retention.expiry(deletedAt: now) == now.addingTimeInterval(30 * day))
    }

    @Test func justDeletedHasAllDaysLeft() {
        #expect(retention.daysRemaining(deletedAt: now, now: now) == 30)
        #expect(!retention.isExpired(deletedAt: now, now: now))
    }

    @Test func partialDaysRoundUp() {
        #expect(retention.daysRemaining(deletedAt: deleted(daysAgo: 0.5), now: now) == 30)
        #expect(retention.daysRemaining(deletedAt: deleted(daysAgo: 1), now: now) == 29)
    }

    @Test func lastDayShowsOne() {
        let deletedAt = deleted(daysAgo: 29 + 1.0 / 24)
        #expect(retention.daysRemaining(deletedAt: deletedAt, now: now) == 1)
        #expect(!retention.isExpired(deletedAt: deletedAt, now: now))
    }

    @Test func justBeforeExpiryIsKept() {
        let deletedAt = deleted(daysAgo: 29.99)
        #expect(retention.daysRemaining(deletedAt: deletedAt, now: now) == 1)
        #expect(!retention.isExpired(deletedAt: deletedAt, now: now))
    }

    @Test func expiresAfterExactlyThirtyDays() {
        #expect(retention.isExpired(deletedAt: deleted(daysAgo: 30), now: now))
    }

    @Test func longExpiredClampsToOneDay() {
        let deletedAt = deleted(daysAgo: 45)
        #expect(retention.isExpired(deletedAt: deletedAt, now: now))
        #expect(retention.daysRemaining(deletedAt: deletedAt, now: now) == 1)
    }

    @Test func deletionInTheFutureKeepsAllDays() {
        let deletedAt = now.addingTimeInterval(2 * day)
        #expect(retention.daysRemaining(deletedAt: deletedAt, now: now) == 30)
        #expect(!retention.isExpired(deletedAt: deletedAt, now: now))
    }

    @Test func customRetention() {
        let week = DeletionRetention(days: 7)
        #expect(week.daysRemaining(deletedAt: now, now: now) == 7)
        #expect(week.isExpired(deletedAt: deleted(daysAgo: 7), now: now))
        #expect(!week.isExpired(deletedAt: deleted(daysAgo: 6.5), now: now))
    }

    @Test func retentionIsAtLeastOneDay() {
        #expect(DeletionRetention(days: 0).days == 1)
        #expect(DeletionRetention(days: -3).daysRemaining(deletedAt: now, now: now) == 1)
    }
}

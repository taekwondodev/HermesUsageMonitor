import Foundation
import Testing
@testable import HermesUsageCore

struct QuotaResetNotificationServiceTests {
    @Test("notifies once when a later live snapshot shows a reset")
    func detectsSingleReset() async throws {
        let notifier = RecordingNotifier()
        let service = QuotaResetNotificationService(notifier: notifier)

        await service.process(try state(usedPercent: 90, resetAt: 1_000))
        await service.process(try state(usedPercent: 10, resetAt: 2_000))

        let notifications = await notifier.notifications
        #expect(notifications.count == 1)
        #expect(notifications[0].events.count == 1)
        #expect(notifications[0].events[0].subscription == .nousPortal)
        #expect(notifications[0].events[0].windowKind == .rollingFiveHours)
    }

    @Test("groups simultaneous window resets into one notification")
    func groupsSimultaneousResets() async throws {
        let notifier = RecordingNotifier()
        let service = QuotaResetNotificationService(notifier: notifier)

        await service.process(try state(
            windows: [
                try window(kind: .rollingFiveHours, label: "5 hours", usedPercent: 90, resetAt: 1_000),
                try window(kind: .weekly, label: "Weekly", usedPercent: 80, resetAt: 3_000),
                try window(kind: .monthly, label: "Monthly", usedPercent: 70, resetAt: 5_000)
            ]
        ))
        await service.process(try state(
            windows: [
                try window(kind: .rollingFiveHours, label: "5 hours", usedPercent: 10, resetAt: 2_000),
                try window(kind: .weekly, label: "Weekly", usedPercent: 5, resetAt: 4_000),
                try window(kind: .monthly, label: "Monthly", usedPercent: 2, resetAt: 6_000)
            ]
        ))

        let notifications = await notifier.notifications
        #expect(notifications.count == 1)
        #expect(notifications[0].events.count == 3)
    }

    @Test("does not notify twice for the same refresh")
    func deduplicatesRefreshes() async throws {
        let notifier = RecordingNotifier()
        let service = QuotaResetNotificationService(notifier: notifier)
        let baseline = try state(usedPercent: 90, resetAt: 1_000)
        let reset = try state(usedPercent: 10, resetAt: 2_000)

        await service.process(baseline)
        await service.process(reset)
        await service.process(reset)

        #expect(await notifier.notifications.count == 1)
    }

    @Test("does not notify for a normal usage variation")
    func ignoresNormalRefresh() async throws {
        let notifier = RecordingNotifier()
        let service = QuotaResetNotificationService(notifier: notifier)

        await service.process(try state(usedPercent: 40, resetAt: 1_000))
        await service.process(try state(usedPercent: 45, resetAt: 1_000))

        #expect(await notifier.notifications.isEmpty)
    }

    @Test("ignores offline snapshots and does not notify after restart")
    func ignoresOfflineAndRestartBaselines() async throws {
        let notifier = RecordingNotifier()
        let service = QuotaResetNotificationService(notifier: notifier)
        let baseline = try state(usedPercent: 90, resetAt: 1_000)
        let offline = SubscriptionRefreshState(
            subscriptions: [try staleSubscription(usedPercent: 10, resetAt: 2_000)],
            availability: .offline,
            updatedAt: QuotaTimestamp(date: Date(timeIntervalSince1970: 2_000))
        )
        let reset = try state(usedPercent: 10, resetAt: 2_000)

        await service.process(baseline)
        await service.process(offline)
        await service.process(reset)

        let restartedNotifier = RecordingNotifier()
        let restartedService = QuotaResetNotificationService(notifier: restartedNotifier)
        await restartedService.process(reset)

        #expect(await notifier.notifications.count == 1)
        #expect(await restartedNotifier.notifications.isEmpty)
    }

    private func state(
        usedPercent: Double = 90,
        resetAt: TimeInterval = 1_000,
        windows: [QuotaWindow]? = nil
    ) throws -> SubscriptionRefreshState {
        let windows = try windows ?? [window(
            kind: .rollingFiveHours,
            label: "5 hours",
            usedPercent: usedPercent,
            resetAt: resetAt
        )]
        return SubscriptionRefreshState(
            subscriptions: [SubscriptionQuota(
                subscription: .nousPortal,
                result: .snapshot(try snapshot(windows: windows))
            )],
            availability: .live,
            updatedAt: QuotaTimestamp(date: Date(timeIntervalSince1970: resetAt))
        )
    }

    private func staleSubscription(usedPercent: Double, resetAt: TimeInterval) throws -> SubscriptionQuota {
        SubscriptionQuota(
            subscription: .nousPortal,
            result: .snapshot(try snapshot(windows: [
                try window(kind: .rollingFiveHours, label: "5 hours", usedPercent: usedPercent, resetAt: resetAt)
            ]).withFreshness(.stale))
        )
    }

    private func snapshot(windows: [QuotaWindow]) throws -> QuotaSnapshot {
        try QuotaSnapshot(
            subscription: .nousPortal,
            capturedAt: QuotaTimestamp(date: Date(timeIntervalSince1970: 1_000)),
            freshness: .live,
            windows: windows,
            source: try QuotaSource(identifier: "test")
        )
    }

    private func window(
        kind: QuotaWindowKind,
        label: String,
        usedPercent: Double,
        resetAt: TimeInterval
    ) throws -> QuotaWindow {
        try QuotaWindow(
            kind: kind,
            label: label,
            usedPercent: usedPercent,
            resetAt: QuotaReset(date: Date(timeIntervalSince1970: resetAt))
        )
    }

    private actor RecordingNotifier: QuotaResetNotifier {
        var notifications: [QuotaResetNotification] = []

        func notify(_ notification: QuotaResetNotification) async {
            notifications.append(notification)
        }
    }
}

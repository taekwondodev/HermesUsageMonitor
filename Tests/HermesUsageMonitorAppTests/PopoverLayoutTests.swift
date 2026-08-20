import Foundation
import HermesUsageCore
import Testing
@testable import HermesUsageMonitorApp

struct HermesUsageMonitorAppTests {
    @Test("popover keeps a usable height while remaining bounded")
    func popoverHeightContract() {
        #expect(PopoverLayout.minimumHeight == 500)
        #expect(PopoverLayout.idealHeight == PopoverLayout.minimumHeight)
        #expect(PopoverLayout.maximumHeight == 640)
        #expect(PopoverLayout.minimumHeight <= PopoverLayout.maximumHeight)
    }

    @Test("provider identity assets are present in the executable bundle")
    func providerAssetsAreBundled() {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/HermesUsageMonitorApp/Resources")

        let catalog = resources.appendingPathComponent("Media.xcassets")
        for name in ProviderAssetCatalog.all + ["HermesMenuBarIcon"] {
            let imageSet = catalog.appendingPathComponent("\(name).imageset")
            #expect(FileManager.default.fileExists(atPath: imageSet.appendingPathComponent("Contents.json").path))
        }
    }

    @Test("subscription order normalizes duplicates and unknown omissions")
    func subscriptionOrderNormalizes() {
        #expect(
            SubscriptionOrderStore.normalize([.chatGPT, .chatGPT]) ==
                [.chatGPT, .opencodeGo]
        )
    }

    @Test("subscription order supports accessible move commands")
    func subscriptionOrderMovesItems() {
        let order: [Subscription] = [.opencodeGo, .chatGPT]
        #expect(
            SubscriptionOrderStore.moved(order, item: .chatGPT, by: -1) ==
                [.chatGPT, .opencodeGo]
        )
        #expect(
            SubscriptionOrderStore.moved(order, item: .opencodeGo, by: -1) == order
        )

        #expect(
            SubscriptionOrderStore.moved(
                order,
                visibleItems: order,
                item: .opencodeGo,
                by: 1
            ) == [.chatGPT, .opencodeGo]
        )
        #expect(
            SubscriptionOrderStore.movedBefore(
                order,
                visibleItems: order,
                item: .chatGPT,
                target: .opencodeGo
            ) == [.chatGPT, .opencodeGo]
        )
    }

    @Test("persisted subscription order is normalized on load")
    func persistedSubscriptionOrderIsNormalized() {
        let suiteName = "HermesUsageMonitorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(["chatgpt", "unknown", "chatgpt"], forKey: "subscriptionOrder.v1")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(
            SubscriptionOrderStore.load(defaults: defaults) ==
                [.chatGPT, .opencodeGo]
        )
        #expect(defaults.array(forKey: "subscriptionOrder.v1") as? [String] == ["chatgpt", "opencode-go"])
    }

    @Test("notification adapter is disabled outside an app bundle")
    func notificationAdapterRequiresAppBundle() {
        #expect(MacOSNotificationEnvironment.canUseUserNotifications == false)
    }

    @Test("reset notification is a no-op for swift run executables")
    func resetNotificationDoesNotCrashOutsideAppBundle() async {
        let notification = QuotaResetNotification(events: [
            QuotaResetEvent(
                subscription: .chatGPT,
                windowKind: .rollingFiveHours,
                windowLabel: "Session"
            )
        ])

        await MacOSQuotaResetNotifier().notify(notification)
    }

    @Test("single instance guard accepts only the current process")
    func singleInstanceGuard() {
        #expect(SingleInstanceGuard.canAcquire(currentProcessID: 10, existingProcessIDs: [10]))
        #expect(!SingleInstanceGuard.canAcquire(currentProcessID: 10, existingProcessIDs: [10, 20]))
        #expect(SingleInstanceGuard.canAcquire(currentProcessID: 10, existingProcessIDs: []))
    }

    @Test("notification authorization is a no-op outside an app bundle")
    func notificationAuthorizationDoesNotCrashOutsideAppBundle() async {
        await NotificationAuthorizationCoordinator.requestOnLaunchIfNeeded()
    }

    @Test("shutdown cancels refresh before terminating the app")
    @MainActor
    func shutdownOrder() {
        var events: [String] = []
        AppShutdownCoordinator(
            stopRefresh: { events.append("stop") },
            terminate: { events.append("terminate") }
        ).shutdown()

        #expect(events == ["stop", "terminate"])
    }
}

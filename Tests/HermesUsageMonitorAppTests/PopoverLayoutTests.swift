import Foundation
import HermesUsageCore
import Testing
@testable import HermesUsageMonitorApp

struct HermesUsageMonitorAppTests {
    @Test("popover keeps a usable height while remaining bounded")
    func popoverHeightContract() {
        #expect(PopoverLayout.minimumHeight == 500)
        #expect(PopoverLayout.idealHeight == 560)
        #expect(PopoverLayout.maximumHeight == 700)
        #expect(PopoverLayout.minimumHeight <= PopoverLayout.maximumHeight)
    }

    @Test("accounting display blocks preserve model metrics and missing values")
    func accountingDisplayBlocksPreserveModelMetrics() throws {
        let items = try [
            LocalAccounting(
                subscription: .chatGPT,
                tokens: try AccountingTokens(input: 2_799_260, output: 553_512),
                requests: 450,
                models: ["deepseek-v4-flash"],
                cost: try AccountingCost(amount: 0, currency: "USD")
            ),
            LocalAccounting(
                subscription: .chatGPT,
                requests: 8,
                models: ["mimo-v2.5", "gpt-5-mini"]
            )
        ]

        #expect(
            AccountingDisplayBlock.blocks(from: items) == [
                AccountingDisplayBlock(
                    id: "0",
                    modelLabel: "deepseek-v4-flash",
                    requestsLabel: "450 richieste",
                    inputLabel: "2.799.260",
                    outputLabel: "553.512",
                    costLabel: "0,00 USD"
                ),
                AccountingDisplayBlock(
                    id: "1",
                    modelLabel: "mimo-v2.5, gpt-5-mini",
                    requestsLabel: "8 richieste",
                    inputLabel: "Non disponibile",
                    outputLabel: "Non disponibile",
                    costLabel: "Non disponibile"
                )
            ]
        )
    }

    @Test(
        "rounds displayed costs to two Italian decimal digits without changing amounts",
        arguments: [
            ("1.234567", "1,23 USD"),
            ("1.239999", "1,24 USD"),
            ("0.004", "0,00 USD"),
            ("0.006", "0,01 USD")
        ]
    )
    func accountingDisplayBlocksRoundCosts(sample: (amount: String, label: String)) throws {
        let amount = try #require(Decimal(string: sample.amount))
        for subscription in [Subscription.chatGPT, .claude] {
            let item = try LocalAccounting(
                subscription: subscription,
                cost: AccountingCost(amount: amount, currency: "USD")
            )
            let block = try #require(AccountingDisplayBlock.blocks(from: [item]).first)
            #expect(block.costLabel == sample.label)
            #expect(item.cost?.amount == amount)
        }
    }

    @Test("formats token counts with Italian thousands separators")
    func accountingDisplayBlocksFormatTokenCounts() throws {
        let items = try [
            LocalAccounting(
                subscription: .chatGPT,
                tokens: try AccountingTokens(input: 1_000, output: 1_000_000)
            ),
            LocalAccounting(
                subscription: .chatGPT,
                tokens: try AccountingTokens(input: 0, output: 999)
            )
        ]

        let blocks = AccountingDisplayBlock.blocks(from: items)

        #expect(blocks[0].inputLabel == "1.000")
        #expect(blocks[0].outputLabel == "1.000.000")
        #expect(blocks[1].inputLabel == "0")
        #expect(blocks[1].outputLabel == "999")
    }

    @Test("provider identity source catalog contains the declared artwork")
    func providerAssetsAreBundled() throws {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/HermesUsageMonitorApp/Resources")

        let catalog = resources.appendingPathComponent("Media.xcassets")
        #expect(ProviderAssetCatalog.all == ["ChatGPTIcon", "AnthropicIcon"])
        for name in ProviderAssetCatalog.all + ["HermesMenuBarIcon"] {
            let imageSet = catalog.appendingPathComponent("\(name).imageset")
            let data = try Data(contentsOf: imageSet.appendingPathComponent("Contents.json"))
            let contents = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let images = try #require(contents["images"] as? [[String: Any]])
            let filenames = images.compactMap { $0["filename"] as? String }
            #expect(filenames.isEmpty == false)
            for filename in filenames {
                #expect(FileManager.default.fileExists(atPath: imageSet.appendingPathComponent(filename).path))
            }
        }
    }

    @Test("subscription order normalizes duplicates and unknown omissions")
    func subscriptionOrderNormalizes() {
        #expect(
            SubscriptionOrderStore.normalize([.chatGPT, .chatGPT]) ==
                [.chatGPT, .claude]
        )
    }

    @Test("subscription order supports moving Claude and ChatGPT")
    func subscriptionOrderMovesItems() {
        let order: [Subscription] = [.chatGPT, .claude]
        #expect(SubscriptionOrderStore.moved(order, item: .chatGPT, by: -1) == order)
        #expect(SubscriptionOrderStore.moved(order, item: .claude, by: -1) == [.claude, .chatGPT])
        #expect(
            SubscriptionOrderStore.movedBefore(
                order,
                visibleItems: order,
                item: .claude,
                target: .chatGPT
            ) == [.claude, .chatGPT]
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
                [.chatGPT, .claude]
        )
        #expect(defaults.array(forKey: "subscriptionOrder.v1") as? [String] == ["chatgpt", "claude"])
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
            stopResourceProfiling: { events.append("profile") },
            terminate: { events.append("terminate") }
        ).shutdown()

        #expect(events == ["stop", "profile", "terminate"])
    }
}

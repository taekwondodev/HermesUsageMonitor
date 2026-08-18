import Foundation
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

        for name in ProviderAssetCatalog.all {
            let matches = ["png", "jpg"].contains { ext in
                FileManager.default.fileExists(
                    atPath: resources.appendingPathComponent("\(name).\(ext)").path
                )
            }
            #expect(matches)
        }
    }
}

import Foundation
import Testing
@testable import HermesUsageCore

struct HermesQuotaSnapshotReaderIntegrationTests {
    @Test("reads a valid Hermes quota snapshot")
    func readsValidSnapshot() throws {
        let fileURL = try makeTemporarySnapshot(
            """
            {
              "version": 1,
              "subscription": "chatgpt",
              "capturedAt": "2030-03-17T12:00:00Z",
              "freshness": "persisted",
              "source": "hermes-account-usage",
              "windows": [
                {
                  "kind": "rolling-5h",
                  "label": "5 hours",
                  "usedPercent": 25,
                  "resetAt": "2030-03-17T14:00:00Z"
                },
                {
                  "kind": "weekly",
                  "label": "Weekly",
                  "usedPercent": 40
                }
              ]
            }
            """
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = HermesQuotaSnapshotReader(fileURL: fileURL).read()

        guard case let .snapshot(snapshot) = result else {
            Issue.record("Expected a valid quota snapshot")
            return
        }

        #expect(snapshot.subscription == .chatGPT)
        #expect(snapshot.freshness == .persisted)
        #expect(snapshot.source.identifier == "hermes-account-usage")
        #expect(snapshot.windows.count == 2)
        #expect(snapshot.windows[0].kind == .rollingFiveHours)
        #expect(snapshot.windows[0].usedPercent == 25)
        #expect(snapshot.windows[1].kind == .weekly)
        #expect(snapshot.windows[1].resetAt == nil)
    }

    @Test("returns sourceMissing when Hermes has no snapshot")
    func returnsMissingSource() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        let result = HermesQuotaSnapshotReader(fileURL: fileURL).read()

        #expect(result == .unavailable(.sourceMissing))
    }

    @Test("returns malformedSnapshot for invalid quota data")
    func returnsMalformedSnapshot() throws {
        let fileURL = try makeTemporarySnapshot(
            """
            {
              "version": 1,
              "subscription": "nous-portal",
              "capturedAt": "2030-03-17T12:00:00Z",
              "freshness": "persisted",
              "source": "hermes-account-usage",
              "windows": [
                {
                  "kind": "monthly",
                  "label": "Monthly",
                  "usedPercent": 101
                }
              ]
            }
            """
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = HermesQuotaSnapshotReader(fileURL: fileURL).read()

        #expect(result == .unavailable(.malformedSnapshot))
    }

    @Test("returns unsupportedVersion for a newer Hermes snapshot")
    func returnsUnsupportedVersion() throws {
        let fileURL = try makeTemporarySnapshot(
            """
            {
              "version": 2,
              "subscription": "opencode-go",
              "capturedAt": "2030-03-17T12:00:00Z",
              "freshness": "persisted",
              "source": "hermes-account-usage",
              "windows": []
            }
            """
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = HermesQuotaSnapshotReader(fileURL: fileURL).read()

        #expect(result == .unavailable(.unsupportedVersion))
    }

    @Test("discovers quota snapshots across Hermes profiles")
    func discoversProfiles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try writeSnapshot(
            subscription: "nous-portal",
            usedPercent: 20,
            to: root.appendingPathComponent("profiles/alpha/usage/quota-snapshot.json")
        )
        try writeSnapshot(
            subscription: "chatgpt",
            usedPercent: 40,
            to: root.appendingPathComponent("profiles/beta/usage/quota-snapshot.json")
        )

        let observations = await HermesProfileQuotaSnapshotReader(
            hermesHome: root,
            now: { Date(timeIntervalSince1970: 500) }
        ).read()

        #expect(observations.count == 1)
        #expect(observations.map(\.profile.value) == ["beta"])
        #expect(observations.map(\.subscription) == [.chatGPT])
    }

    private func makeTemporarySnapshot(_ json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data(json.utf8).write(to: url, options: [.atomic])
        return url
    }

    private func writeSnapshot(
        subscription: String,
        usedPercent: Double,
        to url: URL
    ) throws {
        let json = """
        {
          "version": 1,
          "subscription": "\(subscription)",
          "capturedAt": "2030-03-17T12:00:00Z",
          "freshness": "persisted",
          "source": "hermes-account-usage",
          "windows": [
            {
              "kind": "rolling-5h",
              "label": "5 hours",
              "usedPercent": \(usedPercent)
            }
          ]
        }
        """
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(json.utf8).write(to: url, options: [.atomic])
    }
}

import Foundation
import Testing
@testable import HermesUsageCore

struct HermesManualResetBridgeIntegrationTests {
    @Test("exercises all manual reset states through an executable boundary")
    func exercisesExecutableBoundaryStates() async throws {
        let positive = try await readThroughExecutable("""
        {"version":2,"providers":{"openai-codex":{"status":"available","subscription":"chatgpt","capturedAt":"2030-03-17T12:00:00Z","windows":[{"kind":"rolling-5h","label":"Session","usedPercent":40.0}],"manualResets":{"status":"available","capturedAt":"2030-03-17T12:00:00Z","availableCount":2,"applicableAvailableCount":1,"credits":[{"id":"later","title":"Full reset","status":"available","isSupportedByPlan":true,"expiresAt":"2030-03-20T00:00:00Z"},{"id":"sooner","title":"Full reset","status":"available","isSupportedByPlan":true,"expiresAt":"2030-03-19T00:00:00Z"}]}}}}
        """)
        guard case let .snapshot(positiveSnapshot) = positive.manualReset else {
            Issue.record("Expected positive process output")
            return
        }
        let service = ManualResetRefreshService(clock: { Date(timeIntervalSince1970: 100) })
        guard case let .live(positiveSummary) = await service.refresh(.snapshot(positiveSnapshot)) else {
            Issue.record("Expected a live out-of-order summary")
            return
        }
        let nearest = try #require(ISO8601DateFormatter().date(from: "2030-03-19T00:00:00Z"))
        #expect(positiveSnapshot.credits.map(\.identifier.rawValue) == ["later", "sooner"])
        #expect(positiveSummary.expiration == .dated(QuotaTimestamp(date: nearest)))

        let zero = try await readThroughExecutable("""
        {"version":2,"providers":{"openai-codex":{"status":"available","subscription":"chatgpt","capturedAt":"2030-03-17T12:00:00Z","windows":[{"kind":"rolling-5h","label":"Session","usedPercent":40.0}],"manualResets":{"status":"available","capturedAt":"2030-03-17T12:00:00Z","availableCount":0,"applicableAvailableCount":0,"credits":[]}}}}
        """)
        guard case let .snapshot(zeroSnapshot) = zero.manualReset else {
            Issue.record("Expected zero process output")
            return
        }
        #expect(zeroSnapshot.availableCount == 0)

        let unavailable = try await readThroughExecutable("""
        {"version":2,"providers":{"openai-codex":{"status":"available","subscription":"chatgpt","capturedAt":"2030-03-17T12:00:00Z","windows":[{"kind":"rolling-5h","label":"Session","usedPercent":40.0}],"manualResets":{"status":"unavailable","reason":"manual reset provider unavailable"}}}}
        """)
        #expect(unavailable.manualReset == .unavailable(.sourceUnavailable))

        let malformed = try await readThroughExecutable("""
        {"version":2,"providers":{"openai-codex":{"status":"available","subscription":"chatgpt","capturedAt":"2030-03-17T12:00:00Z","windows":[{"kind":"rolling-5h","label":"Session","usedPercent":40.0}],"manualResets":{"status":"available","capturedAt":"2030-03-17T12:00:00Z","availableCount":1,"applicableAvailableCount":1,"credits":[{"id":" ","title":"Full reset","status":"available","isSupportedByPlan":true}]}}}}
        """)
        #expect(malformed.manualReset == .unavailable(.malformedData))

        let unsupported = try await readThroughExecutable("""
        {"version":99,"providers":{}}
        """)
        #expect(unsupported.manualReset == .unavailable(.unsupportedVersion))

        let incomplete = try await readThroughExecutable("""
        {"version":2,"providers":{"openai-codex":{"status":"available","subscription":"chatgpt","capturedAt":"2030-03-17T12:00:00Z","windows":[{"kind":"rolling-5h","label":"Session","usedPercent":40.0}],"manualResets":{"status":"available","capturedAt":"2030-03-17T12:00:00Z","availableCount":2,"applicableAvailableCount":1,"credits":[{"id":"only-one","title":"Full reset","status":"available","isSupportedByPlan":true,"expiresAt":"2030-03-19T00:00:00Z"}]}}}}
        """)
        guard case let .snapshot(incompleteSnapshot) = incomplete.manualReset,
              case let .live(incompleteSummary) = await service.refresh(.snapshot(incompleteSnapshot)) else {
            Issue.record("Expected incomplete process output to remain observable")
            return
        }
        #expect(incompleteSummary.availableCount == 2)
        #expect(incompleteSummary.expiration == .unavailable)
        #expect(!incompleteSummary.hasActionableCredit)
    }

    @Test("decodes quota and detailed manual resets from one v2 bridge payload")
    func decodesDetailedManualResets() async throws {
        let fixture = Data(
            """
            {
              "version": 2,
              "providers": {
                "openai-codex": {
                  "status": "available",
                  "subscription": "chatgpt",
                  "capturedAt": "2030-03-17T12:00:00Z",
                  "windows": [{"kind":"rolling-5h","label":"Session","usedPercent":40.0,"resetAt":"2030-03-17T17:00:00Z"}],
                  "manualResets": {
                    "status": "available",
                    "capturedAt": "2030-03-17T12:00:00Z",
                    "availableCount": 2,
                    "applicableAvailableCount": 1,
                    "credits": [
                      {"id":"credit-later","title":"Full reset","status":"available","isSupportedByPlan":true,"grantedAt":"2030-03-01T00:00:00Z","expiresAt":"2030-03-20T00:00:00Z"},
                      {"id":"credit-sooner","title":"Full reset","status":"available","isSupportedByPlan":true,"grantedAt":"2030-03-02T00:00:00Z","expiresAt":"2030-03-19T00:00:00Z"}
                    ]
                  }
                }
              }
            }
            """.utf8
        )

        let read = await HermesUsageCommandReader(
            hermesHome: FileManager.default.temporaryDirectory,
            fixtureOutput: fixture
        ).readUsage()

        #expect(read.quotaObservations.count == 1)
        guard case let .snapshot(snapshot) = read.manualReset else {
            Issue.record("Expected a manual reset snapshot")
            return
        }
        #expect(snapshot.availableCount == 2)
        #expect(snapshot.applicableAvailableCount == 1)
        #expect(snapshot.credits.map(\.identifier.rawValue) == ["credit-later", "credit-sooner"])
        #expect(snapshot.credits[1].expiresAt == ISO8601DateFormatter().date(from: "2030-03-19T00:00:00Z"))
    }

    @Test("decodes zero manual resets as a valid snapshot")
    func decodesZeroState() async throws {
        let read = await reader(manualResets: """
        {"status":"available","capturedAt":"2030-03-17T12:00:00Z","availableCount":0,"applicableAvailableCount":0,"credits":[]}
        """).readUsage()

        guard case let .snapshot(snapshot) = read.manualReset else {
            Issue.record("Expected a valid zero snapshot")
            return
        }
        #expect(snapshot.availableCount == 0)
        #expect(snapshot.credits.isEmpty)
    }

    @Test("keeps quota live while malformed reset details become unavailable")
    func isolatesMalformedResetDetails() async throws {
        let read = await reader(manualResets: """
        {"status":"available","capturedAt":"2030-03-17T12:00:00Z","availableCount":1,"applicableAvailableCount":1,"credits":[{"id":" ","title":"Full reset","status":"available","isSupportedByPlan":true}]}
        """).readUsage()

        #expect(read.quotaObservations.count == 1)
        #expect(read.quotaObservations[0].result.isSnapshot)
        #expect(read.manualReset == .unavailable(.malformedData))
    }

    @Test("keeps a known positive count non-actionable when detailed rows are incomplete")
    func decodesIncompleteDetailsForSafeServiceState() async throws {
        let read = await reader(manualResets: """
        {"status":"available","capturedAt":"2030-03-17T12:00:00Z","availableCount":2,"applicableAvailableCount":1,"credits":[{"id":"credit-1","title":"Full reset","status":"available","isSupportedByPlan":true,"expiresAt":"2030-03-19T00:00:00Z"}]}
        """).readUsage()

        guard case let .snapshot(snapshot) = read.manualReset else {
            Issue.record("Expected the provider count to remain observable")
            return
        }
        let service = ManualResetRefreshService(clock: {
            Date(timeIntervalSince1970: 100)
        })
        guard case let .live(summary) = await service.refresh(.snapshot(snapshot)) else {
            Issue.record("Expected a live but incomplete summary")
            return
        }
        #expect(summary.availableCount == 2)
        #expect(summary.expiration == .unavailable)
        #expect(!summary.hasActionableCredit)
    }

    @Test("marks both quota and manual resets unsupported for an unknown contract version")
    func rejectsUnsupportedVersion() async {
        let fixture = Data("{\"version\":99,\"providers\":{}}".utf8)
        let read = await HermesUsageCommandReader(
            hermesHome: FileManager.default.temporaryDirectory,
            fixtureOutput: fixture
        ).readUsage()

        #expect(read.quotaObservations.allSatisfy { $0.result == .unavailable(.unsupportedVersion) })
        #expect(read.manualReset == .unavailable(.unsupportedVersion))
    }

    @Test("does not accept manual resets from an unsupported technical provider")
    func rejectsUnsupportedProviderIdentity() async {
        let fixture = Data(
            """
            {
              "version": 2,
              "providers": {
                "unsupported": {
                  "status": "available",
                  "subscription": "chatgpt",
                  "capturedAt": "2030-03-17T12:00:00Z",
                  "windows": [{"kind":"rolling-5h","label":"Session","usedPercent":40.0}],
                  "manualResets": {"status":"available","capturedAt":"2030-03-17T12:00:00Z","availableCount":1,"applicableAvailableCount":1,"credits":[{"id":"credit-1","title":"Full reset","status":"available","isSupportedByPlan":true}]}
                }
              }
            }
            """.utf8
        )

        let read = await HermesUsageCommandReader(
            hermesHome: FileManager.default.temporaryDirectory,
            fixtureOutput: fixture
        ).readUsage()

        #expect(read.manualReset == .unavailable(.sourceMissing))
    }

    private func reader(manualResets: String) -> HermesUsageCommandReader {
        let fixture = Data(
            """
            {
              "version": 2,
              "providers": {
                "openai-codex": {
                  "status": "available",
                  "subscription": "chatgpt",
                  "capturedAt": "2030-03-17T12:00:00Z",
                  "windows": [{"kind":"rolling-5h","label":"Session","usedPercent":40.0}],
                  "manualResets": \(manualResets)
                }
              }
            }
            """.utf8
        )
        return HermesUsageCommandReader(
            hermesHome: FileManager.default.temporaryDirectory,
            fixtureOutput: fixture
        )
    }

    private func readThroughExecutable(_ fixture: String) async throws -> ProfileUsageRead {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let launcher = root.appendingPathComponent("hermes-usage-bridge")
        try "#!/bin/sh\nprintf '%s' '\(fixture)'\n".write(
            to: launcher,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: launcher.path
        )
        return await HermesUsageCommandReader(
            hermesHome: root,
            executable: launcher
        ).readUsage()
    }
}

private extension QuotaReadResult {
    var isSnapshot: Bool {
        if case .snapshot = self { return true }
        return false
    }
}

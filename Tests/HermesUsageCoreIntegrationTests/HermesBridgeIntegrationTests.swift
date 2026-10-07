import Foundation
import Testing
@testable import HermesUsageCore

struct HermesBridgeIntegrationTests {
    @Test("invokes the installed bridge launcher with the JSON contract")
    func invokesBridgeLauncher() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let launcher = root.appendingPathComponent("hermes-usage-bridge")
        let fixture = """
        {"providers":{"openai-codex":{"status":"available","subscription":"chatgpt","capturedAt":"2030-03-17T12:00:00Z","windows":[{"kind":"rolling-5h","label":"5 hours","usedPercent":40.0,"resetAt":"2030-03-17T17:00:00Z"},{"kind":"rolling-7d","label":"Longer window","usedPercent":25.0,"resetAt":"2030-03-24T17:00:00Z"}]}}}
        """
        try "#!/bin/sh\n[ \"$1\" = \"--json\" ] || exit 2\nprintf '%s' '\(fixture)'\n".write(
            to: launcher,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)

        let observations = await HermesUsageCommandReader(
            hermesHome: root,
            executable: launcher
        ).readUsage().quotaObservations

        let chatGPT = try #require(observations.first { $0.subscription == .chatGPT })
        guard case let .snapshot(snapshot) = chatGPT.result else {
            Issue.record("Expected a live snapshot from the bridge launcher")
            return
        }
        #expect(snapshot.windows.first?.usedPercent == 40.0)
        #expect(snapshot.windows[1].kind == (try .unknown("rolling-7d")))
        #expect(snapshot.windows[1].label == "Longer window")
        #expect(snapshot.windows[1].usedPercent == 25.0)
        #expect(snapshot.windows[1].resetAt?.at.date == ISO8601DateFormatter().date(from: "2030-03-24T17:00:00Z"))
    }

    @Test("redeems the nearest applicable credit through the bridge launcher")
    func redeemsThroughBridgeLauncher() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let launcher = root.appendingPathComponent("hermes-usage-bridge")
        let fixture = "{\"status\":\"reset\"}"
        try "#!/bin/sh\n[ \"$1\" = \"--redeem\" ] || exit 2\nprintf '%s' '\(fixture)'\n".write(
            to: launcher,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)

        let redeemer = HermesUsageCommandReader(
            hermesHome: root,
            executable: launcher
        )
        let result = await redeemer.redeem(requestID: UUID())

        #expect(result == .confirmed)
    }

    @Test("ignores unsupported providers and preserves supported unavailable providers")
    func decodesUsageCommandOutput() async throws {
        let fixture = Data(
            """
            {
              "providers": {
                "nous": {
                  "status": "available",
                  "subscription": "nous-portal",
                  "capturedAt": "2030-03-17T12:00:00Z",
                  "windows": [{"kind":"monthly","label":"Subscription","usedPercent":83.0}]
                },
                "openai-codex": {
                  "status": "unavailable",
                  "subscription": "chatgpt",
                  "reason": "authentication failed (401)"
                }
              }
            }
            """.utf8
        )
        let observations = await HermesUsageCommandReader(
            hermesHome: FileManager.default.temporaryDirectory,
            fixtureOutput: fixture
        ).readUsage().quotaObservations

        #expect(observations.count == 1)
        guard let chatGPT = observations.first(where: { $0.subscription == .chatGPT })
        else {
            Issue.record("Expected the supported ChatGPT observation")
            return
        }
        #expect(chatGPT.result == .unavailable(.authenticationFailed))
    }

    @Test("decodes distinct Claude limits and keeps ChatGPT healthy on partial failure")
    func decodesClaudeLimitsAndPartialFailure() async throws {
        let fixture = Data("""
        {"providers":{
          "openai-codex":{"status":"available","subscription":"chatgpt","capturedAt":"2030-03-17T12:00:00Z","windows":[{"kind":"weekly","label":"Weekly","usedPercent":1}]},
          "anthropic":{"status":"available","subscription":"claude","capturedAt":"2030-03-17T12:00:00Z","windows":[
            {"kind":"rolling-5h","label":"5 hours","usedPercent":0.5,"resetAt":"2030-03-17T17:00:00Z"},
            {"kind":"weekly","label":"Weekly","usedPercent":66},
            {"kind":"fable-weekly","label":"Fable","usedPercent":74,"resetAt":"2030-03-24T17:00:00Z"}
          ]}
        }}
        """.utf8)
        let usage = await HermesUsageCommandReader(
            hermesHome: FileManager.default.temporaryDirectory,
            fixtureOutput: fixture
        ).readUsage()
        #expect(usage.quotaObservations.count == 2)
        let claude = try #require(usage.quotaObservations.first { $0.subscription == .claude })
        guard case let .snapshot(snapshot) = claude.result else {
            Issue.record("Expected live Claude limits")
            return
        }
        #expect(snapshot.windows.map(\.kind) == [.rollingFiveHours, .weekly, try .unknown("fable-weekly")])
        #expect(snapshot.windows.map(\.usedPercent) == [0.5, 66, 74])
        #expect(snapshot.windows[1].resetAt == nil)
        #expect(snapshot.windows[2].resetAt?.at.date == ISO8601DateFormatter().date(from: "2030-03-24T17:00:00Z"))
        #expect(usage.manualReset == .unavailable(.sourceMissing))

        let unavailable = Data("""
        {"providers":{
          "openai-codex":{"status":"available","subscription":"chatgpt","capturedAt":"2030-03-17T12:00:00Z","windows":[{"kind":"weekly","label":"Weekly","usedPercent":1}]},
          "anthropic":{"status":"unavailable","subscription":"claude","reason":"authentication unavailable"}
        }}
        """.utf8)
        let observations = await HermesUsageCommandReader(
            hermesHome: FileManager.default.temporaryDirectory,
            fixtureOutput: unavailable
        ).readUsage().quotaObservations
        let healthy = try #require(observations.first { $0.subscription == .chatGPT })
        guard case .snapshot = healthy.result else {
            Issue.record("Claude failure must not hide ChatGPT")
            return
        }
        #expect(observations.first { $0.subscription == .claude }?.result == .unavailable(.authenticationFailed))
    }

    @Test("rejects mismatched provider subscription pairs")
    func rejectsMismatchedProviderSubscriptions() async {
        let fixture = Data("""
        {"providers":{
          "openai-codex":{"status":"unavailable","subscription":"claude"},
          "anthropic":{"status":"unavailable","subscription":"chatgpt","manualResets":{"status":"available","capturedAt":"2030-03-17T12:00:00Z","availableCount":0,"applicableAvailableCount":0,"credits":[]}}
        }}
        """.utf8)
        let usage = await HermesUsageCommandReader(
            hermesHome: FileManager.default.temporaryDirectory,
            fixtureOutput: fixture
        ).readUsage()
        #expect(usage.quotaObservations.isEmpty)
        #expect(usage.manualReset == .unavailable(.sourceMissing))
    }

    @Test("marks malformed usage JSON without hiding providers")
    func marksMalformedUsagePayload() async throws {
        let observations = await HermesUsageCommandReader(
            hermesHome: FileManager.default.temporaryDirectory,
            fixtureOutput: Data("not-json".utf8)
        ).readUsage().quotaObservations

        #expect(observations.count == Subscription.allCases.count)
        #expect(observations.allSatisfy { $0.result == .unavailable(.malformedSnapshot) })
    }

    @Test("reads the real state.db accounting schema read-only")
    func readsStateDatabase() throws {
        let hermesHome = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = hermesHome.appendingPathComponent("state.db")
        try FileManager.default.createDirectory(
            at: hermesHome,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: hermesHome) }

        try runSQLite(
            databaseURL: databaseURL,
            sql: """
            CREATE TABLE session_model_usage (
              billing_provider TEXT,
              model TEXT,
              input_tokens INTEGER,
              output_tokens INTEGER,
              api_call_count INTEGER,
              estimated_cost_usd REAL,
              actual_cost_usd REAL,
              last_seen REAL
            );
            INSERT INTO session_model_usage VALUES ('nous','openai/gpt-5.6-luna',100,25,2,0.12,0,1000);
            """
        )

        let values = try HermesStateDBAccountingReader(hermesHome: hermesHome)
            .read(window: AccountingWindow(endingAt: Date(timeIntervalSince1970: 2_000)))
        #expect(values.isEmpty)
    }

    @Test("reads a state.db that uses WAL journal mode")
    func readsWalStateDatabase() throws {
        let hermesHome = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = hermesHome.appendingPathComponent("state.db")
        try FileManager.default.createDirectory(
            at: hermesHome,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: hermesHome) }

        // Hermes keeps state.db in WAL mode, which previously broke the
        // `-readonly` open (exit 14). Guard the WAL read path explicitly.
        try runSQLite(
            databaseURL: databaseURL,
            sql: """
            PRAGMA journal_mode=WAL;
            CREATE TABLE session_model_usage (
              billing_provider TEXT,
              model TEXT,
              input_tokens INTEGER,
              output_tokens INTEGER,
              api_call_count INTEGER,
              estimated_cost_usd REAL,
              actual_cost_usd REAL,
              last_seen REAL
            );
            INSERT INTO session_model_usage VALUES ('nous','openai/gpt-5.6-luna',100,25,2,0.12,0,1000);
            """
        )

        let values = try HermesStateDBAccountingReader(hermesHome: hermesHome)
            .read(window: AccountingWindow(endingAt: Date(timeIntervalSince1970: 2_000)))
        #expect(values.isEmpty)
    }

    @Test(
        "filters Claude accounting routes to the rolling window before aggregation",
        arguments: ["anthropic", "claude-subscription-directsdk-experimental"]
    )
    func filtersRowsByLastSeen(claudeProvider: String) throws {
        let hermesHome = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = hermesHome.appendingPathComponent("state.db")
        try FileManager.default.createDirectory(
            at: hermesHome,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: hermesHome) }

        try runSQLite(
            databaseURL: databaseURL,
            sql: """
            CREATE TABLE session_model_usage (
              billing_provider TEXT,
              model TEXT,
              input_tokens INTEGER,
              output_tokens INTEGER,
              api_call_count INTEGER,
              estimated_cost_usd REAL,
              actual_cost_usd REAL,
              last_seen REAL
            );
            INSERT INTO session_model_usage VALUES ('chatgpt','gpt-5',10,20,1,0.10,0,1000);
            INSERT INTO session_model_usage VALUES ('chatgpt','gpt-5',30,40,2,0.20,0,-2590000);
            INSERT INTO session_model_usage VALUES ('chatgpt','gpt-5',100,100,9,0.90,0,-2590001);
            INSERT INTO session_model_usage VALUES ('chatgpt','gpt-5',50,50,4,0.40,0,2001);
            INSERT INTO session_model_usage VALUES ('openai-codex','gpt-5-mini',5,6,1,0.05,0,NULL);
            INSERT INTO session_model_usage VALUES ('\(claudeProvider)','claude-fable-5',10,20,1,0.10,0,1000);
            INSERT INTO session_model_usage VALUES ('\(claudeProvider)','claude-fable-5',30,40,2,0.20,0,-2590000);
            INSERT INTO session_model_usage VALUES ('\(claudeProvider)','claude-fable-5',100,100,9,0.90,0,-2590001);
            INSERT INTO session_model_usage VALUES ('\(claudeProvider)','claude-fable-5',50,50,4,0.40,0,2001);
            """
        )

        let before = try Data(contentsOf: databaseURL)
        let values = try HermesStateDBAccountingReader(hermesHome: hermesHome)
            .read(window: AccountingWindow(endingAt: Date(timeIntervalSince1970: 2_000)))

        #expect(try Data(contentsOf: databaseURL) == before)
        #expect(values.count == 3)
        #expect(Set(values.map(\.subscription)) == [.chatGPT, .claude])
        let standardModel = try #require(values.first { $0.models == ["gpt-5"] })
        #expect(standardModel.tokens?.input == 40)
        #expect(standardModel.tokens?.output == 60)
        #expect(standardModel.requests == 3)
        let expectedCost = try #require(Decimal(string: "0.3"))
        let actualCost = try #require(standardModel.cost?.amount)
        let tolerance = try #require(Decimal(string: "0.0001"))
        #expect(abs(actualCost - expectedCost) < tolerance)
        let miniModel = try #require(values.first { $0.models == ["gpt-5-mini"] })
        #expect(miniModel.tokens?.total == 11)
        #expect(miniModel.requests == 1)
        let claude = try #require(values.first { $0.subscription == .claude })
        #expect(claude.provider == claudeProvider)
        #expect(claude.tokens?.input == 40)
        #expect(claude.tokens?.output == 60)
        #expect(claude.requests == 3)
        #expect(abs(try #require(claude.cost?.amount) - expectedCost) < tolerance)
    }

    private func runSQLite(databaseURL: URL, sql: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [databaseURL.path, sql]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}

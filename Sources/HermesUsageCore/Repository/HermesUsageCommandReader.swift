import Foundation

struct HermesUsageCommandReader: ProfileQuotaSource, Sendable {
    private let hermesHome: URL
    private let executable: URL?

    init(
        hermesHome: URL,
        executable: URL? = nil
    ) {
        self.hermesHome = hermesHome
        self.executable = executable
    }

    func read() async -> [ProfileQuotaObservation] {
        guard let output = runCommand(),
              let payload = try? decode(output) else {
            return []
        }

        let profile = try? HermesProfileID(value: "hermes-usage-command")
        guard let profile else { return [] }
        let observedAt = QuotaTimestamp(date: Date())

        return payload.providers.compactMap { _, provider in
            guard let subscription = Subscription(rawValue: provider.subscription) else {
                return nil
            }

            let result: QuotaReadResult
            if provider.status != "available" {
                result = .unavailable(.sourceUnreadable)
            } else {
                let windows = (provider.windows ?? []).compactMap { window -> QuotaWindow? in
                    guard let usedPercent = window.usedPercent else { return nil }
                    return try? QuotaWindow(
                        kind: window.kind,
                        label: window.label,
                        usedPercent: usedPercent,
                        resetAt: window.resetAt.map(QuotaReset.init(date:))
                    )
                }
                guard let capturedAt = provider.capturedAt,
                      !windows.isEmpty,
                      let source = try? QuotaSource(identifier: "hermes-usage-command"),
                      let snapshot = try? QuotaSnapshot(
                          subscription: subscription,
                          capturedAt: QuotaTimestamp(date: capturedAt),
                          freshness: .live,
                          windows: windows,
                          source: source
                      )
                else {
                    result = .unavailable(.malformedSnapshot)
                    return try? ProfileQuotaObservation(
                        profile: profile,
                        subscription: subscription,
                        observedAt: observedAt,
                        result: result
                    )
                }
                result = .snapshot(snapshot)
            }

            return try? ProfileQuotaObservation(
                profile: profile,
                subscription: subscription,
                observedAt: observedAt,
                result: result
            )
        }
    }
}

private extension HermesUsageCommandReader {
    struct Payload: Decodable {
        let providers: [String: Provider]
    }

    struct Provider: Decodable {
        let status: String
        let subscription: String
        let capturedAt: Date?
        let windows: [Window]?
    }

    struct Window: Decodable {
        let kind: QuotaWindowKind
        let label: String
        let usedPercent: Double?
        let resetAt: Date?
    }

    func decode(_ data: Data) throws -> Payload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Payload.self, from: data)
    }

    func runCommand() -> Data? {
        let process = Process()
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        if let executable = executable ?? discoverHermesExecutable() {
            process.executableURL = executable
            process.arguments = ["usage", "--json", "--provider", "nous", "--provider", "openai-codex"]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["hermes", "usage", "--json", "--provider", "nous", "--provider", "openai-codex"]
        }
        var environment = ProcessInfo.processInfo.environment
        environment["HERMES_HOME"] = hermesHome.path
        process.environment = environment

        do {
            try process.run()
            let deadline = Date().addingTimeInterval(15)
            while process.isRunning {
                guard Date() < deadline else {
                    process.terminate()
                    return nil
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        return output.fileHandleForReading.readDataToEndOfFile()
    }

    func discoverHermesExecutable() -> URL? {
        let profileRoot = hermesHome
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidate = profileRoot
            .appendingPathComponent("hermes-agent/venv/bin/hermes")
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }
}

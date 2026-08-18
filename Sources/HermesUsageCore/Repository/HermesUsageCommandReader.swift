import Foundation

struct HermesUsageCommandReader: ProfileQuotaSource, Sendable {
    private let hermesHome: URL
    private let executable: URL?
    private let fixtureOutput: Data?

    init(
        hermesHome: URL,
        executable: URL? = nil,
        fixtureOutput: Data? = nil
    ) {
        self.hermesHome = hermesHome
        self.executable = executable
        self.fixtureOutput = fixtureOutput
    }

    func read() async -> [ProfileQuotaObservation] {
        let payload: Payload
        if let fixtureOutput {
            guard let decoded = try? decode(fixtureOutput) else {
                return unavailableObservations(.malformedSnapshot)
            }
            payload = decoded
        } else {
            switch runCommand() {
            case let .success(output):
                guard let decoded = try? decode(output) else {
                    return unavailableObservations(.malformedSnapshot)
                }
                payload = decoded
            case let .failure(reason):
                return unavailableObservations(reason.quotaReason)
            }
        }

        if let version = payload.version, version != 1 {
            return unavailableObservations(.unsupportedVersion)
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
                result = .unavailable(provider.unavailableReason)
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

    private func unavailableObservations(_ reason: QuotaUnavailableReason) -> [ProfileQuotaObservation] {
        guard let profile = try? HermesProfileID(value: "hermes-usage-command") else { return [] }
        let observedAt = QuotaTimestamp(date: Date())
        return Subscription.allCases.compactMap {
            try? ProfileQuotaObservation(
                profile: profile,
                subscription: $0,
                observedAt: observedAt,
                result: .unavailable(reason)
            )
        }
    }
}

private extension HermesUsageCommandReader {
    enum CommandFailure: Error {
        case commandMissing
        case authenticationFailed
        case endpointUnavailable

        var quotaReason: QuotaUnavailableReason {
            switch self {
            case .commandMissing: return .commandMissing
            case .authenticationFailed: return .authenticationFailed
            case .endpointUnavailable: return .endpointUnavailable
            }
        }
    }


    struct Payload: Decodable {
        let version: Int?
        let providers: [String: Provider]
    }

    struct Provider: Decodable {
        let status: String
        let subscription: String
        let capturedAt: Date?
        let windows: [Window]?
        let reason: String?

        var unavailableReason: QuotaUnavailableReason {
            let normalized = (reason ?? "").lowercased()
            if normalized.contains("auth") || normalized.contains("api key") || normalized.contains("401") || normalized.contains("403") {
                return .authenticationFailed
            }
            if normalized.contains("endpoint") || normalized.contains("network") || normalized.contains("timeout") {
                return .endpointUnavailable
            }
            return .sourceUnreadable
        }
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

    func runCommand() -> Result<Data, CommandFailure> {
        let process = Process()
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let resolvedExecutable = executable ?? discoverHermesExecutable()
        let commandMissing = resolvedExecutable == nil
        if let executable = resolvedExecutable {
            process.executableURL = executable
            process.arguments = ["usage", "--json", "--provider", "nous", "--provider", "openai-codex", "--provider", "opencode-go"]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["hermes", "usage", "--json", "--provider", "nous", "--provider", "openai-codex", "--provider", "opencode-go"]
        }
        var environment = ProcessInfo.processInfo.environment
        environment["HERMES_HOME"] = hermesCommandHome.path
        process.environment = environment

        do {
            try process.run()
            let deadline = Date().addingTimeInterval(15)
            while process.isRunning {
                guard Date() < deadline else {
                    process.terminate()
                    return .failure(.endpointUnavailable)
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
        } catch {
            return .failure(.commandMissing)
        }
        guard process.terminationStatus == 0 else {
            return .failure(commandMissing ? .commandMissing : .endpointUnavailable)
        }
        return .success(output.fileHandleForReading.readDataToEndOfFile())
    }

    func discoverHermesExecutable() -> URL? {
        let candidates = [
            hermesHome.appendingPathComponent("hermes-agent/venv/bin/hermes"),
            hermesHome
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("hermes-agent/venv/bin/hermes")
        ]
        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    var hermesCommandHome: URL {
        hermesHome.deletingLastPathComponent().lastPathComponent == "profiles"
            ? hermesHome.deletingLastPathComponent().deletingLastPathComponent()
            : hermesHome
    }
}

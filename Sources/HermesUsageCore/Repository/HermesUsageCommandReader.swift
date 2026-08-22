import Foundation

struct HermesUsageCommandReader: ProfileUsageSource, Sendable {
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

    func readUsage() async -> ProfileUsageRead {
        let payload: Payload
        if let fixtureOutput {
            guard let decoded = try? decode(fixtureOutput) else {
                return unavailableRead(
                    quota: .malformedSnapshot,
                    manualReset: .malformedData
                )
            }
            payload = decoded
        } else {
            switch runCommand() {
            case let .success(output):
                guard let decoded = try? decode(output) else {
                    return unavailableRead(
                        quota: .malformedSnapshot,
                        manualReset: .malformedData
                    )
                }
                payload = decoded
            case let .failure(reason):
                return unavailableRead(
                    quota: reason.quotaReason,
                    manualReset: reason.manualResetReason
                )
            }
        }

        guard payload.version == Self.contractVersion else {
            return unavailableRead(
                quota: .unsupportedVersion,
                manualReset: .unsupportedVersion
            )
        }

        return ProfileUsageRead(
            quotaObservations: quotaObservations(from: payload),
            manualReset: manualResetResult(from: payload)
        )
    }
}

private extension HermesUsageCommandReader {
    static let contractVersion = 2

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

        var manualResetReason: ManualResetUnavailableReason {
            switch self {
            case .commandMissing: return .sourceMissing
            case .authenticationFailed, .endpointUnavailable: return .sourceUnavailable
            }
        }
    }

    struct Payload: Decodable {
        let version: Int
        let providers: [String: Provider]
    }

    struct Provider: Decodable {
        let status: String
        let subscription: String
        let capturedAt: Date?
        let windows: [Window]?
        let reason: String?
        let manualResets: ManualResetEnvelope

        enum CodingKeys: String, CodingKey {
            case status
            case subscription
            case capturedAt
            case windows
            case reason
            case manualResets
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            status = try container.decode(String.self, forKey: .status)
            subscription = try container.decode(String.self, forKey: .subscription)
            capturedAt = try container.decodeIfPresent(Date.self, forKey: .capturedAt)
            windows = try container.decodeIfPresent([Window].self, forKey: .windows)
            reason = try container.decodeIfPresent(String.self, forKey: .reason)
            if container.contains(.manualResets) {
                do {
                    manualResets = .payload(try container.decode(
                        ManualResetPayload.self,
                        forKey: .manualResets
                    ))
                } catch {
                    manualResets = .malformed
                }
            } else {
                manualResets = .missing
            }
        }

        var unavailableReason: QuotaUnavailableReason {
            let normalized = (reason ?? "").lowercased()
            if normalized.contains("auth") || normalized.contains("api key")
                || normalized.contains("401") || normalized.contains("403") {
                return .authenticationFailed
            }
            if normalized.contains("endpoint") || normalized.contains("network")
                || normalized.contains("timeout") {
                return .endpointUnavailable
            }
            return .sourceUnreadable
        }
    }

    enum ManualResetEnvelope {
        case payload(ManualResetPayload)
        case missing
        case malformed
    }

    struct ManualResetPayload: Decodable {
        let status: String
        let capturedAt: Date?
        let availableCount: Int?
        let applicableAvailableCount: Int?
        let credits: [Credit]?
        let reason: String?
    }

    struct Credit: Decodable {
        let id: String
        let title: String
        let status: String
        let isSupportedByPlan: Bool
        let grantedAt: Date?
        let expiresAt: Date?
    }

    struct Window: Decodable {
        let kind: QuotaWindowKind
        let label: String
        let usedPercent: Double?
        let resetAt: Date?
    }

    func quotaObservations(from payload: Payload) -> [ProfileQuotaObservation] {
        guard let profile = try? HermesProfileID(value: "hermes-usage-command") else {
            return []
        }
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
                      ) else {
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

    func manualResetResult(from payload: Payload) -> ManualResetReadResult {
        guard let provider = payload.providers["openai-codex"] else {
            return .unavailable(.sourceMissing)
        }
        switch provider.manualResets {
        case .missing:
            return .unavailable(.sourceMissing)
        case .malformed:
            return .unavailable(.malformedData)
        case let .payload(payload):
            guard payload.status == "available" else {
                return .unavailable(manualResetUnavailableReason(payload.reason))
            }
            guard let availableCount = payload.availableCount,
                  let applicableCount = payload.applicableAvailableCount,
                  let rawCredits = payload.credits,
                  let capturedAt = payload.capturedAt else {
                return .unavailable(.malformedData)
            }
            do {
                let credits = try rawCredits.map { raw in
                    guard let status = ManualResetCreditStatus(rawValue: raw.status) else {
                        throw ManualResetDomainError.invalidStatus
                    }
                    return try ManualResetCredit(
                        identifier: raw.id,
                        title: raw.title,
                        status: status,
                        isSupportedByPlan: raw.isSupportedByPlan,
                        grantedAt: raw.grantedAt,
                        expiresAt: raw.expiresAt
                    )
                }
                return .snapshot(try ManualResetSnapshot(
                    availableCount: availableCount,
                    applicableAvailableCount: applicableCount,
                    credits: credits,
                    capturedAt: capturedAt
                ))
            } catch {
                return .unavailable(.malformedData)
            }
        }
    }

    func manualResetUnavailableReason(_ reason: String?) -> ManualResetUnavailableReason {
        let normalized = (reason ?? "").lowercased()
        if normalized.contains("missing") {
            return .sourceMissing
        }
        return .sourceUnavailable
    }

    func unavailableRead(
        quota reason: QuotaUnavailableReason,
        manualReset manualReason: ManualResetUnavailableReason
    ) -> ProfileUsageRead {
        ProfileUsageRead(
            quotaObservations: unavailableObservations(reason),
            manualReset: .unavailable(manualReason)
        )
    }

    func unavailableObservations(_ reason: QuotaUnavailableReason) -> [ProfileQuotaObservation] {
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

        guard let resolvedExecutable = executable ?? discoverBridgeExecutable() else {
            return .failure(.commandMissing)
        }
        process.executableURL = resolvedExecutable
        process.arguments = ["--json"]
        var environment = ProcessInfo.processInfo.environment
        environment["HERMES_HOME"] = hermesCommandHome.path
        process.environment = environment

        do {
            try process.run()
            let deadline = Date().addingTimeInterval(15)
            while process.isRunning {
                guard Date() < deadline else {
                    process.terminate()
                    process.waitUntilExit()
                    return .failure(.endpointUnavailable)
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
        } catch {
            return .failure(.commandMissing)
        }
        guard process.terminationStatus == 0 else {
            return .failure(.endpointUnavailable)
        }
        return .success(output.fileHandleForReading.readDataToEndOfFile())
    }

    func discoverBridgeExecutable() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        let configuredCandidates = [
            environment["HERMES_USAGE_BRIDGE"].map(URL.init(fileURLWithPath:)),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/hermes-usage-bridge"),
            hermesHome.appendingPathComponent("hermes-usage-bridge"),
        ].compactMap { $0 }
        return configuredCandidates.first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    var hermesCommandHome: URL {
        hermesHome.deletingLastPathComponent().lastPathComponent == "profiles"
            ? hermesHome.deletingLastPathComponent().deletingLastPathComponent()
            : hermesHome
    }
}

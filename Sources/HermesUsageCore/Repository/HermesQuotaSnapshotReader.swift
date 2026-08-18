import Foundation

public struct HermesQuotaSnapshotReader: QuotaSnapshotSource, Sendable {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        let hermesHome = environment["HERMES_HOME"].map(URL.init(fileURLWithPath:))
            ?? homeDirectory.appendingPathComponent(".hermes", isDirectory: true)
        self.init(
            fileURL: hermesHome
                .appendingPathComponent(HermesQuotaSnapshotContract.relativePath)
        )
    }

    public func read() -> QuotaReadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .unavailable(.sourceMissing)
        }

        do {
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(Payload.self, from: data)
            return try .snapshot(payload.snapshot())
        } catch let error as QuotaDomainError {
            switch error {
            case .unsupportedVersion:
                return .unavailable(.unsupportedVersion)
            case .invalidPercentage, .invalidSnapshot:
                return .unavailable(.malformedSnapshot)
            }
        } catch DecodingError.dataCorrupted, DecodingError.keyNotFound,
                DecodingError.typeMismatch, DecodingError.valueNotFound {
            return .unavailable(.malformedSnapshot)
        } catch CocoaError.fileReadNoPermission, CocoaError.fileReadCorruptFile {
            return .unavailable(.sourceUnreadable)
        } catch {
            return .unavailable(.sourceUnreadable)
        }
    }
}

private extension HermesQuotaSnapshotReader {
    struct Payload: Decodable {
        let version: Int
        let subscription: Subscription
        let capturedAt: Date
        let freshness: QuotaFreshness
        let source: String
        let windows: [Window]

        func snapshot() throws -> QuotaSnapshot {
            guard version == 1 else {
                throw QuotaDomainError.unsupportedVersion
            }

            let mappedWindows = try windows.map { window in
                try QuotaWindow(
                    kind: window.kind,
                    label: window.label,
                    usedPercent: window.usedPercent,
                    resetAt: window.resetAt.map(QuotaReset.init(date:))
                )
            }

            return try QuotaSnapshot(
                subscription: subscription,
                capturedAt: QuotaTimestamp(date: capturedAt),
                freshness: freshness,
                windows: mappedWindows,
                source: try QuotaSource(identifier: source)
            )
        }
    }

    struct Window: Decodable {
        let kind: QuotaWindowKind
        let label: String
        let usedPercent: Double
        let resetAt: Date?
    }
}

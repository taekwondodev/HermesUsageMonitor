import Foundation

public protocol LocalAccountingSource: Sendable {
    func read() throws -> [LocalAccounting]
}

public protocol LocalAccountingObserver: Sendable {
    func record(_ result: GroupedLocalAccountingResult)
}

struct NoopLocalAccountingObserver: LocalAccountingObserver {
    func record(_ result: GroupedLocalAccountingResult) {}
}

extension HermesAccountingReader: LocalAccountingSource {}

public struct LocalAccountingService: Sendable {
    private let source: any LocalAccountingSource
    private let observer: any LocalAccountingObserver

    public init(
        source: any LocalAccountingSource,
        observer: any LocalAccountingObserver = OSLogLocalAccountingObserver()
    ) {
        self.source = source
        self.observer = observer
    }

    public func readGroupedBySubscription() -> GroupedLocalAccountingResult {
        do {
            let grouped = Dictionary(grouping: try source.read(), by: \.subscription)
            let result = GroupedLocalAccountingResult.available(grouped)
            observer.record(result)
            return result
        } catch let error as HermesAccountingReadError {
            let result = GroupedLocalAccountingResult.unavailable(error.reason)
            observer.record(result)
            return result
        } catch {
            let result = GroupedLocalAccountingResult.unavailable(.malformedData)
            observer.record(result)
            return result
        }
    }
}

private extension HermesAccountingReadError {
    var reason: LocalAccountingUnavailableReason {
        switch self {
        case .sourceMissing:
            return .sourceMissing
        case .sourceUnreadable:
            return .sourceUnreadable
        case .malformedData:
            return .malformedData
        case .unsupportedVersion:
            return .unsupportedVersion
        }
    }
}

import Foundation

public protocol LocalAccountingSource: Sendable {
    func read(window: AccountingWindow) throws -> [LocalAccounting]
}

public protocol LocalAccountingObserver: Sendable {
    func record(_ result: GroupedLocalAccountingResult)
}

struct NoopLocalAccountingObserver: LocalAccountingObserver {
    func record(_ result: GroupedLocalAccountingResult) {}
}

extension HermesAccountingReader: LocalAccountingSource {}

public actor LocalAccountingService {
    private let source: any LocalAccountingSource
    private let observer: any LocalAccountingObserver
    private let clock: @Sendable () -> Date

    public init(
        source: any LocalAccountingSource,
        observer: any LocalAccountingObserver = OSLogLocalAccountingObserver(),
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.source = source
        self.observer = observer
        self.clock = clock
    }

    public func readGroupedBySubscription() -> GroupedLocalAccountingResult {
        do {
            let grouped = Dictionary(
                grouping: try source.read(window: AccountingWindow(endingAt: clock())),
                by: \.subscription
            )
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

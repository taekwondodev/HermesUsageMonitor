import Foundation

public protocol LocalAccountingSource: Sendable {
    func read() -> [LocalAccounting]
}

extension HermesAccountingReader: LocalAccountingSource {}

public struct LocalAccountingService: Sendable {
    private let source: any LocalAccountingSource

    public init(source: any LocalAccountingSource) {
        self.source = source
    }

    public func readGroupedBySubscription() -> [Subscription: [LocalAccounting]] {
        Dictionary(grouping: source.read(), by: \.subscription)
    }
}

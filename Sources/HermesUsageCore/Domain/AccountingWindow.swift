import Foundation

public struct AccountingWindow: Equatable, Sendable {
    public static let duration: TimeInterval = 30 * 24 * 60 * 60

    public let start: Date
    public let end: Date

    public init(endingAt end: Date) {
        self.end = end
        start = end.addingTimeInterval(-Self.duration)
    }

    public func includes(lastSeen: Date?) -> Bool {
        guard let lastSeen else { return true }
        return lastSeen >= start && lastSeen <= end
    }
}

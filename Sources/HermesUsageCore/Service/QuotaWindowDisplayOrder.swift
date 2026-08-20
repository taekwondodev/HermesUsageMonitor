import Foundation

public enum QuotaWindowDisplayOrder {
    private static let opencodeGo: [QuotaWindowKind] = [
        .rollingFiveHours,
        .weekly,
        .monthly
    ]

    public static func windows(
        for subscription: Subscription,
        windows: [QuotaWindow]
    ) -> [QuotaWindow] {
        switch subscription {
        case .opencodeGo:
            return opencodeGoWindows(windows)
        case .chatGPT:
            return windows.sorted(by: isHigherRisk)
        }
    }

    private static func opencodeGoWindows(_ windows: [QuotaWindow]) -> [QuotaWindow] {
        windows.sorted { lhs, rhs in
            index(of: lhs.kind) < index(of: rhs.kind)
        }
    }

    private static func index(of kind: QuotaWindowKind) -> Int {
        guard let index = opencodeGo.firstIndex(of: kind) else {
            preconditionFailure("Unsupported OpenCode Go quota window kind")
        }
        return index
    }

    private static func isHigherRisk(_ lhs: QuotaWindow, _ rhs: QuotaWindow) -> Bool {
        if lhs.usedPercent != rhs.usedPercent {
            return lhs.usedPercent > rhs.usedPercent
        }
        return (lhs.resetAt?.at.date ?? .distantFuture) < (rhs.resetAt?.at.date ?? .distantFuture)
    }
}
import Foundation

public enum QuotaTemporalPolicy {
    public static func secondsRemaining(until date: Date, now: Date) -> Int {
        max(0, Int(ceil(date.timeIntervalSince(now))))
    }

    public static func snapshotAgeLabel(capturedAt: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(capturedAt)))
        guard seconds > 0 else { return "appena acquisito" }

        if seconds < 60 {
            return "\(seconds)s fa"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) min fa"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours) h fa"
        }

        return "\(hours / 24) g fa"
    }
}

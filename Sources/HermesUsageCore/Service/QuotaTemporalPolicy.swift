import Foundation

public enum QuotaTemporalPolicy {
    public static func secondsRemaining(until date: Date, now: Date) -> Int {
        max(0, Int(ceil(date.timeIntervalSince(now))))
    }

    public static func countdownLabel(seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        if safeSeconds < 60 {
            return "tra \(safeSeconds)s"
        }

        let minutes = (safeSeconds + 59) / 60
        if minutes < 60 {
            return "tra \(minutes) min"
        }

        if safeSeconds < 86_400 {
            let hours = safeSeconds / 3_600
            let remainingSeconds = safeSeconds % 3_600
            let roundedMinutes = (remainingSeconds + 59) / 60
            let remainingMinutes = hours == 23 && roundedMinutes == 60
                ? 59
                : roundedMinutes
            return remainingMinutes == 0
                ? "tra \(hours) h"
                : "tra \(hours) h \(remainingMinutes) min"
        }

        let hours = minutes / 60
        let days = (hours + 23) / 24
        return "tra \(days) g"
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

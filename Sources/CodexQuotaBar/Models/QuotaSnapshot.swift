import Foundation

struct QuotaSnapshot {
    var fiveHourUsedPercent: Int?
    var fiveHourResetAt: Date?
    var weeklyUsedPercent: Int?
    var weeklyResetAt: Date?
    var resetCredits: Int?
    var lifetimeTokens: Int?
    var updatedAt: Date?
    var errorMessage: String?

    static let empty = QuotaSnapshot()

    func fiveHourCountdown(at now: Date) -> String {
        Self.countdown(until: fiveHourResetAt, now: now, allowsDays: false)
    }

    func weeklyCountdown(at now: Date) -> String {
        Self.countdown(until: weeklyResetAt, now: now, allowsDays: true)
    }

    static func countdown(until deadline: Date?, now: Date, allowsDays: Bool) -> String {
        guard let deadline else { return "--" }
        let seconds = max(0, deadline.timeIntervalSince(now))
        if allowsDays && seconds >= 86400 { return "\(Int(seconds / 86400))Day" }
        if seconds >= 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes / 60)h\(minutes % 60)m"
        }
        if seconds > 0 { return "\(max(1, Int(seconds / 60)))min" }
        return "0min"
    }

    var resetToolTip: String {
        "时 截止：\(fiveHourResetValue)\n周 截止：\(weeklyResetValue)"
    }

    var menuTitle: String {
        "\(menuFiveHourTitle) | \(menuWeeklyTitle)"
    }

    var menuFiveHourTitle: String {
        fiveHourUsedPercent.map { "时 \(100 - $0)%" } ?? "时 --"
    }

    var menuFiveHourValue: String {
        fiveHourUsedPercent.map { "\(100 - $0)%" } ?? "--"
    }

    var fiveHourRemainingPercent: Int? {
        fiveHourUsedPercent.map { 100 - $0 }
    }

    var menuWeeklyTitle: String {
        weeklyUsedPercent.map { "周 \(100 - $0)%" } ?? "周 --"
    }

    var menuWeeklyValue: String {
        weeklyUsedPercent.map { "\(100 - $0)%" } ?? "--"
    }

    var weeklyRemainingPercent: Int? {
        weeklyUsedPercent.map { 100 - $0 }
    }

    var fiveHourLine: String {
        guard let fiveHourUsedPercent else {
            return "5h: unavailable"
        }

        return "5h: \(fiveHourUsedPercent)% used, \(100 - fiveHourUsedPercent)% left"
    }

    var weeklyLine: String {
        guard let weeklyUsedPercent else {
            return "Weekly: unavailable"
        }

        return "Weekly: \(weeklyUsedPercent)% used, \(100 - weeklyUsedPercent)% left"
    }

    var fiveHourResetLine: String {
        "\(fiveHourResetLabel) \(fiveHourResetValue)"
    }

    var fiveHourResetLabel: String {
        "时 刷新"
    }

    var fiveHourResetValue: String {
        fiveHourResetAt.map { DateFormatter.quotaHour.string(from: $0) } ?? "--"
    }

    var weeklyResetLine: String {
        "\(weeklyResetLabel) \(weeklyResetValue)"
    }

    var weeklyResetLabel: String {
        "周 刷新"
    }

    var weeklyResetValue: String {
        weeklyResetAt.map { DateFormatter.quotaHour.string(from: $0) } ?? "--"
    }

    var updatedLabel: String {
        "上次刷新"
    }

    var updatedValue: String {
        updatedAt.map { DateFormatter.quotaHour.string(from: $0) } ?? "--"
    }

    var updatedLine: String {
        if let errorMessage {
            return "错误：\(errorMessage)"
        }

        return "\(updatedLabel) \(updatedValue)"
    }
}

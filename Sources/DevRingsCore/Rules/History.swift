import Foundation

public struct History: Sendable {
    public var days: [String: DayRecord]
    public var settings: Settings
    public var today: String
    public var calendar: Calendar

    public init(days: [String: DayRecord], settings: Settings, today: String, calendar: Calendar = .current) {
        self.days = days
        self.settings = settings
        self.today = today
        self.calendar = calendar
    }

    public func isWorkingDay(_ day: String) -> Bool {
        guard let date = LocalDay.start(day, calendar: calendar) else { return false }
        return settings.workingDays.contains(calendar.component(.weekday, from: date))
    }

    /// Why a day is paused, if it is. A past working day with no activity at all counts as time off,
    /// so a forgotten day off doesn't break a streak, unless that's turned off.
    public func pause(on day: String) -> PauseReason? {
        if let reason = days[day]?.pause { return reason }
        if settings.pauseRanges.contains(where: { $0.contains(day) }) { return .range }
        if settings.autoPauseIdleDays, day < today, let record = days[day], record.rings.allSatisfy({ $0.count == 0 }) {
            return .noActivity
        }
        return nil
    }

    /// Whether a day takes part in streaks, nudges and awards.
    public func counts(_ day: String) -> Bool {
        day <= today && isWorkingDay(day) && pause(on: day) == nil
    }

    /// Counted days that have a record, oldest first.
    public var countedRecords: [DayRecord] {
        days.values.filter { counts($0.date) }.sorted { $0.date < $1.date }
    }

    /// Consecutive counted days with every ring closed. Today only adds once it's perfect,
    /// and never breaks the streak while it's still in progress.
    public var streak: Int {
        guard let earliest = days.keys.min() else { return 0 }
        var day = today
        if days[today]?.isPerfect != true, let yesterday = LocalDay.adding(-1, to: today, calendar: calendar) {
            day = yesterday
        }
        var streak = 0
        while day >= earliest {
            if counts(day) {
                guard days[day]?.isPerfect == true else { break }
                streak += 1
            }
            guard let previous = LocalDay.adding(-1, to: day, calendar: calendar) else { break }
            day = previous
        }
        return streak
    }

    /// The last counted day before today with a record, for "Yesterday" and the morning recap.
    public var lastCountedDay: DayRecord? {
        countedRecords.last { $0.date < today }
    }
}

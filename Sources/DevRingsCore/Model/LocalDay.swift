import Foundation

/// Days are `yyyy-MM-dd` strings in the user's calendar, so they sort and key history directly.
public enum LocalDay {
    public static func string(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    public static func start(_ day: String, calendar: Calendar = .current) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    public static func adding(_ days: Int, to day: String, calendar: Calendar = .current) -> String? {
        guard let start = start(day, calendar: calendar),
              let date = calendar.date(byAdding: .day, value: days, to: start) else { return nil }
        return string(date, calendar: calendar)
    }
}

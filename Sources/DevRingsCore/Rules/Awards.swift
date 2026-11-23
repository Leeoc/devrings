import Foundation

public enum AwardKind: String, CaseIterable, Codable, Sendable {
    case firstRing, perfectDay, perfectWeek, streak5, streak10, streak25, streak50, streak100
    case doubleShip, tripleShip, reviewerOfTheWeek, newBest

    static let streaks: [(Int, AwardKind)] = [(5, .streak5), (10, .streak10), (25, .streak25), (50, .streak50), (100, .streak100)]
}

public struct EarnedAward: Hashable, Sendable {
    public var kind: AwardKind
    public var count: Int
    public var lastEarned: String
}

extension History {
    /// New Best needs some history first, or every early day would be a record.
    static let newBestMinimumDays = 10

    /// Worked out from history alone, so changing a ring or goal never takes an award back.
    public func awards() -> [AwardKind: EarnedAward] {
        var earned: [AwardKind: EarnedAward] = [:]
        func earn(_ kind: AwardKind, _ day: String) {
            var award = earned[kind] ?? EarnedAward(kind: kind, count: 0, lastEarned: day)
            award.count += 1
            award.lastEarned = max(award.lastEarned, day)
            earned[kind] = award
        }

        var run = 0
        var best: [RingID: Int] = [:]
        for (i, record) in countedRecords.enumerated() {
            if earned[.firstRing] == nil, record.rings.contains(where: \.isClosed) { earn(.firstRing, record.date) }
            if record.isPerfect {
                earn(.perfectDay, record.date)
                run += 1
                for (length, kind) in AwardKind.streaks where run == length { earn(kind, record.date) }
            } else if record.date < today {
                run = 0
            }
            if let ship = record.rings.first(where: { $0.id == .ship }), ship.goal > 0 {
                if ship.count >= ship.goal * 2 { earn(.doubleShip, record.date) }
                if ship.count >= ship.goal * 3 { earn(.tripleShip, record.date) }
            }
            for ring in record.rings {
                if i >= Self.newBestMinimumDays, let previous = best[ring.id], ring.count > previous { earn(.newBest, record.date) }
                best[ring.id] = max(best[ring.id] ?? 0, ring.count)
            }
        }

        for week in finishedWeeks() {
            let required = week.filter { pause(on: $0) == nil }
            let records = required.compactMap { days[$0] }
            guard required.count >= 3, records.count == required.count, let last = required.last else { continue }
            if records.allSatisfy(\.isPerfect) { earn(.perfectWeek, last) }
            if records.allSatisfy({ $0.rings.first { $0.id == .review }?.isClosed == true }) { earn(.reviewerOfTheWeek, last) }
        }
        return earned
    }

    /// Working days of each week, from the first recorded week, whose last working day is today or earlier.
    private func finishedWeeks() -> [[String]] {
        guard let first = days.keys.min(), var cursor = LocalDay.start(first, calendar: calendar),
              let end = LocalDay.start(today, calendar: calendar) else { return [] }
        var weeks: [[String]] = []
        while let week = calendar.dateInterval(of: .weekOfYear, for: cursor), week.start <= end {
            let working = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
                .map { LocalDay.string($0, calendar: calendar) }
                .filter(isWorkingDay)
            if let last = working.last, last <= today { weeks.append(working) }
            guard let next = calendar.date(byAdding: .day, value: 7, to: week.start) else { break }
            cursor = next
        }
        return weeks
    }
}

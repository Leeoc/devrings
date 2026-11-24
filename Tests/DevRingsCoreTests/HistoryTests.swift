import Foundation
import Testing
@testable import DevRingsCore

private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/London")!
    c.firstWeekday = 2
    return c
}()

/// Goals are Ship 1 and Review 1, so counts of 1 close a ring.
private func day(_ date: String, ship: Int = 1, review: Int = 1, pause: PauseReason? = nil) -> DayRecord {
    func items(_ n: Int) -> [RingItem] { (0..<n).map { RingItem(ref: "!\($0)", title: "", url: URL(string: "https://x")!) } }
    return DayRecord(date: date, rings: [
        RingResult(id: .ship, name: "Ship", goal: 1, items: items(ship)),
        RingResult(id: .review, name: "Review", goal: 1, items: items(review)),
    ], pause: pause)
}

private func history(_ records: [DayRecord], today: String, settings: Settings = Settings()) -> History {
    History(days: Dictionary(uniqueKeysWithValues: records.map { ($0.date, $0) }), settings: settings, today: today, calendar: calendar)
}

// 2026-11-02 is a Monday.

@Test func streakSkipsWeekendsAndPausedDaysAndWaitsForToday() {
    let week = [day("2026-11-02"), day("2026-11-03"), day("2026-11-04", ship: 0, review: 0, pause: .manual),
                day("2026-11-05"), day("2026-11-06")]
    #expect(history(week + [day("2026-11-09", ship: 0)], today: "2026-11-09").streak == 4)
    #expect(history(week + [day("2026-11-09")], today: "2026-11-09").streak == 5)
}

@Test func streakBreaksOnAMissedWorkingDay() {
    let days = [day("2026-11-02"), day("2026-11-03", review: 0), day("2026-11-04"), day("2026-11-05")]
    #expect(history(days, today: "2026-11-05").streak == 2)
}

@Test func idleDayIsTimeOffUnlessStrictStreaksAreOn() {
    let days = [day("2026-11-02"), day("2026-11-03", ship: 0, review: 0), day("2026-11-04")]
    #expect(history(days, today: "2026-11-04").streak == 2)
    var strict = Settings()
    strict.autoPauseIdleDays = false
    #expect(history(days, today: "2026-11-04", settings: strict).streak == 1)
}

@Test func todayWithNoActivityIsNotPausedYet() {
    #expect(history([day("2026-11-02", ship: 0, review: 0)], today: "2026-11-02").pause(on: "2026-11-02") == nil)
}

@Test func pauseRangeCountsAsTimeOff() {
    var settings = Settings()
    settings.pauseRanges = [PauseRange(start: "2026-11-04", end: "2026-11-03")]
    let days = [day("2026-11-02"), day("2026-11-03", review: 0), day("2026-11-04", ship: 0), day("2026-11-05")]
    #expect(history(days, today: "2026-11-05", settings: settings).streak == 2)
}

@Test func nonWorkingDaysFollowSettings() {
    var settings = Settings()
    settings.workingDays = [2, 3, 4, 5]
    let h = history([], today: "2026-11-06", settings: settings)
    #expect(h.isWorkingDay("2026-11-05"))
    #expect(!h.isWorkingDay("2026-11-06"))
}

@Test func awardsFromAFixedHistory() {
    // Week 1: perfect Mon to Fri, Thursday is a triple-ship day.
    // Week 2: two days off, so only three counted days, all perfect, but Review missed on Thursday.
    let days = [
        day("2026-11-02"), day("2026-11-03"), day("2026-11-04"), day("2026-11-05", ship: 3), day("2026-11-06"),
        day("2026-11-09", pause: .manual), day("2026-11-10", pause: .manual),
        day("2026-11-11"), day("2026-11-12", review: 0), day("2026-11-13"),
    ]
    let awards = history(days, today: "2026-11-13").awards()
    #expect(awards[.firstRing]?.count == 1)
    #expect(awards[.firstRing]?.lastEarned == "2026-11-02")
    #expect(awards[.perfectDay]?.count == 7)
    #expect(awards[.streak5]?.lastEarned == "2026-11-06")
    #expect(awards[.perfectWeek]?.count == 1)
    #expect(awards[.reviewerOfTheWeek]?.count == 1)
    #expect(awards[.doubleShip]?.count == 1)
    #expect(awards[.tripleShip]?.count == 1)
    #expect(awards[.newBest] == nil)
}

@Test func weekInProgressEarnsNothingYet() {
    let days = [day("2026-11-02"), day("2026-11-03"), day("2026-11-04")]
    #expect(history(days, today: "2026-11-04").awards()[.perfectWeek] == nil)
}

@Test func weekWithTooFewCountedDaysIsNotPerfect() {
    let days = [day("2026-11-02"), day("2026-11-03"),
                day("2026-11-04", pause: .manual), day("2026-11-05", pause: .manual), day("2026-11-06", pause: .manual)]
    #expect(history(days, today: "2026-11-06").awards()[.perfectWeek] == nil)
}

@Test func newBestNeedsHistoryFirst() {
    let dates = ["2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06",
                 "2026-11-09", "2026-11-10", "2026-11-11", "2026-11-12", "2026-11-13", "2026-11-16"]
    var days = dates.map { day($0) }
    days[days.count - 1] = day("2026-11-16", review: 4)
    #expect(history(days, today: "2026-11-16").awards()[.newBest]?.lastEarned == "2026-11-16")
}

@Test func olderSettingsFilesLoadWithMenuBarDefaults() throws {
    let settings = try JSONDecoder().decode(Settings.self, from: Data(#"{"autoPauseIdleDays":false}"#.utf8))
    #expect(settings.menuBarStyle == .colour)
    #expect(!settings.menuBarShowsCount)
    #expect(!settings.autoPauseIdleDays)
    let roundTrip = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode({ var s = Settings(); s.menuBarStyle = .monochrome; return s }()))
    #expect(roundTrip.menuBarStyle == .monochrome)
}

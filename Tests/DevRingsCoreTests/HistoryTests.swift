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
    #expect(!settings.hasOnboarded)
    #expect(!settings.autoPauseIdleDays)
    let roundTrip = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode({ var s = Settings(); s.menuBarStyle = .monochrome; return s }()))
    #expect(roundTrip.menuBarStyle == .monochrome)
}

private func at(_ day: String, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(byAdding: DateComponents(hour: hour, minute: minute), to: LocalDay.start(day, calendar: calendar)!)!
}

@Test func closingARingNotifiesOnceAndAllRingsReplacesTheLast() {
    let thursday = [day("2026-11-05"), day("2026-11-06", ship: 1, review: 0)]
    let h = history(thursday, today: "2026-11-06")
    let notices = h.notices(at: at("2026-11-06", 11), sent: ["recap"])
    #expect(notices.map(\.id) == ["closed-ship"])
    #expect(notices[0].title == "You closed Ship")
    #expect(notices[0].body == "1 of 1 merged today.")
    #expect(h.notices(at: at("2026-11-06", 11), sent: ["recap", "closed-ship"]).isEmpty)

    let perfect = history([day("2026-11-05"), day("2026-11-06")], today: "2026-11-06")
    let all = perfect.notices(at: at("2026-11-06", 11), sent: ["recap", "closed-ship"])
    #expect(all.map(\.id) == ["closed-all"])
    #expect(all[0].body == "That's 2 days in a row.")
    #expect(perfect.noticeIDsCovered(by: all[0]) == ["closed-all", "closed-ship", "closed-review"])
}

@Test func nudgeWaitsForItsTimeAndNamesWhatsLeft() {
    let h = history([day("2026-11-06", ship: 0, review: 0)], today: "2026-11-06")
    #expect(h.notices(at: at("2026-11-06", 14, 59), sent: ["recap"]).isEmpty)
    let nudge = h.notices(at: at("2026-11-06", 15), sent: ["recap"])
    #expect(nudge.map(\.title) == ["Two rings to go"])
    #expect(nudge[0].body == "1 more to merge and 1 more to review. There's still time.")
    #expect(h.notices(at: at("2026-11-06", 16), sent: ["recap", "behind"]).isEmpty)
}

@Test func pausedAndNonWorkingDaysStayQuiet() {
    let paused = history([day("2026-11-06", ship: 0, review: 0, pause: .manual)], today: "2026-11-06")
    #expect(paused.notices(at: at("2026-11-06", 16), sent: []).isEmpty)
    let saturday = history([day("2026-11-07", ship: 5, review: 0)], today: "2026-11-07")
    #expect(saturday.notices(at: at("2026-11-07", 16), sent: []).isEmpty)
    var off = Settings()
    (off.notifyClosed, off.notifyBehind, off.notifyRecap) = (false, false, false)
    #expect(history([day("2026-11-06", review: 0)], today: "2026-11-06", settings: off).notices(at: at("2026-11-06", 16), sent: []).isEmpty)
}

@Test func recapCoversTheLastCountedDayAndSkipsIdleOnes() {
    // Friday was idle, so Monday's recap is about Thursday.
    let days = [day("2026-11-05", review: 0), day("2026-11-06", ship: 0, review: 0), day("2026-11-09", ship: 0, review: 0)]
    let h = history(days, today: "2026-11-09")
    #expect(h.notices(at: at("2026-11-09", 8, 29), sent: []).isEmpty)
    let recap = h.notices(at: at("2026-11-09", 8, 30), sent: [], awardTitle: { _ in "First Ring" })
    #expect(recap.map(\.title) == ["Thursday: 1 of 2 rings closed"])
    #expect(recap[0].body == "You earned First Ring. Today, give Review a push.")

    let perfect = history([day("2026-11-06"), day("2026-11-09", ship: 0, review: 0)], today: "2026-11-09")
    let good = perfect.notices(at: at("2026-11-09", 9), sent: [], awardTitle: { $0 == .perfectDay ? "Perfect Day" : "x" })
    #expect(good[0].title == "Friday: every ring closed")
    #expect(good[0].body.hasPrefix("You earned "))
    #expect(good[0].body.contains("Perfect Day"))
    #expect(good[0].body.hasSuffix("Your streak is 1 day."))
}

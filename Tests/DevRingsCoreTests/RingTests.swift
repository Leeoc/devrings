import Foundation
import Testing
@testable import DevRingsCore

private func ring(_ id: RingID, count: Int, goal: Int) -> RingResult {
    let items = (0..<count).map { RingItem(ref: "!\($0)", title: "", url: URL(string: "https://example.com")!) }
    return RingResult(id: id, name: "", goal: goal, items: items)
}

@Test func lappedRingIsClosedAndPastOne() {
    let r = ring(.review, count: 4, goal: 3)
    #expect(r.isClosed)
    #expect(r.progress > 1)
}

@Test func zeroGoalDoesNotDivideByZero() {
    #expect(ring(.ship, count: 2, goal: 0).progress == 2)
}

@Test func perfectDayNeedsEveryRingClosedAndNoPause() {
    let closed = [ring(.ship, count: 3, goal: 3), ring(.review, count: 5, goal: 3)]
    #expect(DayRecord(date: "2026-11-23", rings: closed).isPerfect)
    #expect(!DayRecord(date: "2026-11-23", rings: closed, pause: .manual).isPerfect)
    #expect(!DayRecord(date: "2026-11-23", rings: closed + [ring(.ticket(UUID()), count: 1, goal: 2)]).isPerfect)
    #expect(!DayRecord(date: "2026-11-23", rings: []).isPerfect)
}

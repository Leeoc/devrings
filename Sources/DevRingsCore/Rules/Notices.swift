import Foundation

public struct Notice: Equatable, Sendable {
    public enum Kind: Sendable { case closed, behind, recap }

    /// Unique within a day, so each notice is sent at most once per day.
    public let id: String
    public let kind: Kind
    public let title: String
    public let body: String
}

extension History {
    /// Notices due at `now` that haven't gone out today. `sent` holds the ids already sent today.
    public func notices(at now: Date, sent: Set<String>, awardTitle: (AwardKind) -> String = { $0.rawValue }) -> [Notice] {
        guard counts(today), let record = days[today] else { return [] }
        var notices: [Notice] = []

        if settings.notifyRecap, isPast(settings.recapHour, settings.recapMinute, now), !sent.contains("recap"),
           let recap = recap(awardTitle: awardTitle) {
            notices.append(recap)
        }

        if settings.notifyClosed {
            if record.isPerfect {
                if !sent.contains("closed-all") {
                    notices.append(Notice(id: "closed-all", kind: .closed, title: "You closed all your rings",
                                          body: streak > 1 ? "That's \(streak) days in a row." : "A perfect day."))
                }
            } else {
                for ring in record.rings where ring.isClosed && !sent.contains(Self.closedID(ring)) {
                    notices.append(Notice(id: Self.closedID(ring), kind: .closed, title: "You closed \(ring.name)",
                                          body: "\(ring.count) of \(ring.goal) \(ring.id.doneVerb) today."))
                }
            }
        }

        let open = record.rings.filter { !$0.isClosed }
        if settings.notifyBehind, !open.isEmpty, isPast(settings.behindHour, settings.behindMinute, now), !sent.contains("behind") {
            let toGo = open.map { "\($0.goal - $0.count) more \($0.id.toDoPhrase(name: $0.name))" }
            let title = switch open.count {
            case 1: "One ring to go"
            case 2: "Two rings to go"
            default: "\(open.count) rings to go"
            }
            notices.append(Notice(id: "behind", kind: .behind, title: title,
                                  body: "\(toGo.formatted(.list(type: .and))). There's still time."))
        }
        return notices
    }

    /// Every id a notice for today could have, so closing a whole day also covers its single rings.
    public func noticeIDsCovered(by notice: Notice) -> Set<String> {
        guard notice.id == "closed-all", let record = days[today] else { return [notice.id] }
        return Set(record.rings.map(Self.closedID)).union([notice.id])
    }

    private func recap(awardTitle: (AwardKind) -> String) -> Notice? {
        guard let day = lastCountedDay else { return nil }
        let closed = day.rings.filter(\.isClosed).count
        let when = LocalDay.adding(-1, to: today, calendar: calendar) == day.date
            ? "Yesterday"
            : LocalDay.start(day.date, calendar: calendar)?.formatted(.dateTime.weekday(.wide)) ?? day.date
        let title = day.isPerfect ? "\(when): every ring closed" : "\(when): \(closed) of \(day.rings.count) rings closed"

        var lines: [String] = []
        let earned = awards().values.filter { $0.lastEarned == day.date }.map { awardTitle($0.kind) }.sorted()
        if !earned.isEmpty { lines.append("You earned \(earned.formatted(.list(type: .and))).") }
        if streak > 0 { lines.append("Your streak is \(streak) \(streak == 1 ? "day" : "days").") }
        if let weakest = day.rings.filter({ !$0.isClosed }).min(by: { $0.progress < $1.progress }) {
            lines.append("Today, give \(weakest.name) a push.")
        }
        return Notice(id: "recap", kind: .recap, title: title, body: lines.isEmpty ? "Have a good day." : lines.joined(separator: " "))
    }

    private func isPast(_ hour: Int, _ minute: Int, _ now: Date) -> Bool {
        let c = calendar.dateComponents([.hour, .minute], from: now)
        return (c.hour ?? 0, c.minute ?? 0) >= (hour, minute)
    }

    private static func closedID(_ ring: RingResult) -> String {
        switch ring.id {
        case .ship: "closed-ship"
        case .review: "closed-review"
        case .ticket(let id): "closed-\(id.uuidString)"
        }
    }
}

private extension RingID {
    var doneVerb: String {
        switch self {
        case .ship: "merged"
        case .review: "reviewed"
        case .ticket: "moved"
        }
    }

    func toDoPhrase(name: String) -> String {
        switch self {
        case .ship: "to merge"
        case .review: "to review"
        case .ticket: "for \(name)"
        }
    }
}

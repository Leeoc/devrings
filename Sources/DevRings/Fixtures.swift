import DevRingsCore
import Foundation

/// Two months of plausible days for `--fixture` runs and screenshots, without touching real data.
enum Fixtures {
    static let jiraSite = URL(string: "https://acme.atlassian.net")!

    private static let shipped = [
        ("acme/app", ":fire: (ABC-81) Drop the legacy feature flag"), ("acme/api", "Retry 429s with backoff"),
        ("acme/app", "(ABC-84) Split the sync worker"), ("acme/web", "Faster first paint on the dashboard"),
        ("acme/api", "(ABC-90) Remove the v1 client"), ("acme/app", "Tidy test fixtures"),
    ]
    private static let reviewed = [
        ("acme/infra", "Network policies for the workers"), ("acme/api", "Log redaction for tokens"),
        ("acme/web", "(ABC-77) Empty state for search"), ("acme/app", "Bump the runner image"),
        ("acme/infra", "Cache warmup on deploy"), ("acme/api", "Retry budget per client"),
    ]
    private static let tickets = [
        ("ABC-81", "Drop the legacy feature flag", "Done"), ("ABC-84", "Split the sync worker", "In Review"),
        ("ABC-86", "Delete the old migrations", "Done"), ("ABC-90", "Remove the v1 client", "Done"),
    ]

    static func history() -> ([String: DayRecord], Settings) {
        var settings = Settings()
        settings.setup.ticket = TicketRing(name: "Tech debt", goal: 2, filter: TicketFilter(labels: ["tech-debt"]))
        var generator = SplitMix(seed: 11)
        let today = LocalDay.string(.now)
        let history = History(days: [:], settings: settings, today: today)
        var days: [String: DayRecord] = [:]
        for offset in 0..<60 {
            guard let day = LocalDay.adding(-offset, to: today), history.isWorkingDay(day),
                  let start = LocalDay.start(day) else { continue }
            var record = settings.setup.emptyRecord(for: day)
            if offset == 12 || offset == 13 {
                record.pause = .manual
            } else if offset == 0 {
                let at = { (hour: Double) in start.addingTimeInterval(hour * 3600) }
                record.rings[0].items = [item(.ship, 0, at: at(9.6)), item(.ship, 2, at: at(14.25))]
                record.rings[1].items = [item(.review, 0, at: at(10.5)), item(.review, 2, at: at(11.2)), item(.review, 4, at: at(15.8))]
                record.rings[2].items = [item(.ticket, 0, at: at(9.7))]
            } else {
                let ceilings = [5, 5, 3]
                for i in record.rings.indices {
                    let count = Int(generator.next() % UInt64(ceilings[i] + 1))
                    let first = Int(generator.next() % 6)
                    let kind = record.rings[i].id.kind
                    record.rings[i].items = (0..<count).map { (n: Int) -> RingItem in
                        let seconds = Double(9 + n * 2) * 3600 + Double(n * 17 * 60)
                        return item(kind, (first + n) % 6, at: start.addingTimeInterval(seconds))
                    }
                }
            }
            days[day] = record
        }
        return (days, settings)
    }

    private static func item(_ kind: RingKind, _ n: Int, at date: Date) -> RingItem {
        switch kind {
        case .ship:
            let (project, title) = shipped[n]
            return RingItem(ref: "\(project)!\(400 + n)", title: title, url: URL(string: "https://gitlab.com/\(project)/-/merge_requests/\(400 + n)")!,
                            project: project, date: date)
        case .review:
            let (project, title) = reviewed[n]
            return RingItem(ref: "\(project)!\(300 + n)", title: title, url: URL(string: "https://gitlab.com/\(project)/-/merge_requests/\(300 + n)")!,
                            project: project, date: date)
        case .ticket:
            let (key, title, status) = tickets[n % tickets.count]
            return RingItem(ref: key, title: title, url: jiraSite.appending(path: "browse/\(key)"), project: "Acme", status: status)
        }
    }
}

private struct SplitMix {
    var seed: UInt64
    mutating func next() -> UInt64 {
        seed &+= 0x9E3779B97F4A7C15
        var z = seed
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

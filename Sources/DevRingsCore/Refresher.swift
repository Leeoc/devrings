import Foundation

public enum Refresher {
    /// Builds the record for `day`. A ring whose provider fails keeps its items from `previous`,
    /// so one bad token doesn't zero the rest of the day.
    public static func record(for day: String, setup: RingSetup, previous: DayRecord?,
                              codeHost: (any CodeHost)?, tracker: (any WorkTracker)?) async -> (record: DayRecord, errors: [String]) {
        let ticketRing = setup.ticket
        async let ship = attempt { try await codeHost?.mergedMRs(on: day) }
        async let review = attempt { try await codeHost?.reviewedMRs(on: day) }
        async let tickets = attempt {
            guard let ticketRing else { return nil }
            return try await tracker?.ticketsMoved(on: day, matching: ticketRing.filter)
        }

        var rings = [(RingID.ship, "Ship", setup.shipGoal, await ship), (.review, "Review", setup.reviewGoal, await review)]
        if let ticketRing { rings.append((.ticket(ticketRing.id), ticketRing.name, ticketRing.goal, await tickets)) }

        var errors: [String] = []
        let results = rings.map { id, name, goal, result in
            let kept = previous?.rings.first { $0.id == id }?.items ?? []
            let items: [RingItem]
            switch result {
            case .success(let fetched): items = fetched ?? kept
            case .failure(let error):
                items = kept
                let message = error.localizedDescription
                if !errors.contains(message) { errors.append(message) }
            }
            return RingResult(id: id, name: name, goal: goal, items: items)
        }
        return (DayRecord(date: day, rings: results, pause: previous?.pause), errors)
    }

    private static func attempt(_ fetch: @Sendable () async throws -> [RingItem]?) async -> Result<[RingItem]?, any Error> {
        do { return .success(try await fetch()) } catch { return .failure(error) }
    }
}

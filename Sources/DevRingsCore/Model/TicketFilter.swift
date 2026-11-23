import Foundation

public struct TicketFilter: Codable, Hashable, Sendable {
    public var labels: [String]
    public var matchAllLabels: Bool
    public var project: String?
    public var epic: String?
    /// When set, replaces everything above.
    public var rawJQL: String?

    public init(labels: [String] = [], matchAllLabels: Bool = false, project: String? = nil,
                epic: String? = nil, rawJQL: String? = nil) {
        self.labels = labels
        self.matchAllLabels = matchAllLabels
        self.project = project
        self.epic = epic
        self.rawJQL = rawJQL
    }

    /// nil means no narrowing: every ticket you moved counts.
    public var jql: String? {
        if let raw = rawJQL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty { return raw }
        var clauses: [String] = []
        if !labels.isEmpty {
            clauses.append(matchAllLabels
                ? labels.map { "labels = \(quoted($0))" }.joined(separator: " AND ")
                : "labels in (\(labels.map(quoted).joined(separator: ", ")))")
        }
        if let project, !project.isEmpty { clauses.append("project = \(quoted(project))") }
        if let epic, !epic.isEmpty { clauses.append("parent = \(quoted(epic))") }
        return clauses.isEmpty ? nil : clauses.joined(separator: " AND ")
    }

    private func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

public struct TicketRing: Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var goal: Int
    public var filter: TicketFilter

    public init(id: UUID = UUID(), name: String, goal: Int, filter: TicketFilter) {
        self.id = id
        self.name = name
        self.goal = goal
        self.filter = filter
    }
}

public struct RingSetup: Codable, Hashable, Sendable {
    public var shipGoal: Int
    public var reviewGoal: Int
    public var ticket: TicketRing?

    public init(shipGoal: Int = 3, reviewGoal: Int = 3, ticket: TicketRing? = nil) {
        self.shipGoal = shipGoal
        self.reviewGoal = reviewGoal
        self.ticket = ticket
    }

    public func emptyRecord(for day: String) -> DayRecord {
        var rings = [RingResult(id: .ship, name: "Ship", goal: shipGoal, items: []),
                     RingResult(id: .review, name: "Review", goal: reviewGoal, items: [])]
        if let ticket { rings.append(RingResult(id: .ticket(ticket.id), name: ticket.name, goal: ticket.goal, items: [])) }
        return DayRecord(date: day, rings: rings)
    }
}

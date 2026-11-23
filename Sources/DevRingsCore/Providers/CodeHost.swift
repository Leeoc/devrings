import Foundation

public protocol CodeHost: Sendable {
    /// The signed-in username, used to confirm a connection.
    func username() async throws -> String
    func mergedMRs(on day: String) async throws -> [RingItem]
    func reviewedMRs(on day: String) async throws -> [RingItem]
}

public struct TrackerOption: Codable, Hashable, Sendable, Identifiable {
    public var key: String
    public var name: String
    public var id: String { key }
}

public protocol WorkTracker: Sendable {
    /// The signed-in display name, used to confirm a connection.
    func displayName() async throws -> String
    func ticketsMoved(on day: String, matching filter: TicketFilter) async throws -> [RingItem]
    func labels() async throws -> [String]
    func projects() async throws -> [TrackerOption]
    func epics(inProject project: String?) async throws -> [TrackerOption]
}

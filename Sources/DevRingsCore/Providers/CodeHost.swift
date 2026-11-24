import Foundation

/// Who you're signed in as, shown in Settings › Accounts.
public struct AccountInfo: Sendable, Equatable {
    public var name: String
    public var handle: String?
    public var avatar: URL?

    public init(name: String, handle: String? = nil, avatar: URL? = nil) {
        self.name = name
        self.handle = handle
        self.avatar = avatar
    }
}

public protocol CodeHost: Sendable {
    func account() async throws -> AccountInfo
    func mergedMRs(on day: String) async throws -> [RingItem]
    func reviewedMRs(on day: String) async throws -> [RingItem]
}

public struct TrackerOption: Codable, Hashable, Sendable, Identifiable {
    public var key: String
    public var name: String
    public var id: String { key }
}

public protocol WorkTracker: Sendable {
    func account() async throws -> AccountInfo
    func ticketsMoved(on day: String, matching filter: TicketFilter) async throws -> [RingItem]
    func labels() async throws -> [String]
    func projects() async throws -> [TrackerOption]
    func epics(inProject project: String?) async throws -> [TrackerOption]
}

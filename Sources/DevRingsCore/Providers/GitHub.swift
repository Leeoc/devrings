import Foundation

public struct GitHubCredentials: Codable, Sendable, Equatable {
    /// https://github.com, or a GitHub Enterprise Server address.
    public var host: URL
    public var token: String

    public init(host: URL = URL(string: "https://github.com")!, token: String) {
        self.host = host
        self.token = token
    }

    var graphQL: URL {
        host.host() == "github.com" ? URL(string: "https://api.github.com/graphql")! : host.appending(path: "api/graphql")
    }
}

public enum GitHubError: LocalizedError, Equatable {
    case query(String)

    public var errorDescription: String? {
        switch self {
        case .query(let message): "GitHub couldn't answer: \(message)"
        }
    }
}

public actor GitHub: CodeHost {
    private let credentials: GitHubCredentials
    private let calendar: Calendar

    public init(_ credentials: GitHubCredentials, calendar: Calendar = .current) {
        self.credentials = credentials
        self.calendar = calendar
    }

    public func account() async throws -> AccountInfo {
        struct Response: Decodable { let viewer: PR.Author }
        let viewer = try Self.decode(Response.self, from: try await query("query { viewer { login name avatarUrl } }")).viewer
        return AccountInfo(name: viewer.name ?? viewer.login, handle: "@\(viewer.login)", avatar: viewer.avatarUrl)
    }

    public func mergedMRs(on day: String) async throws -> [RingItem] {
        // Search dates are UTC, so look a day either side and keep what merged on the local day.
        guard let after = LocalDay.adding(-1, to: day, calendar: calendar),
              let before = LocalDay.adding(1, to: day, calendar: calendar) else { return [] }
        let data = try await query("""
            query($q: String!) { search(type: ISSUE, query: $q, first: 100) { nodes { ... on PullRequest { \(PR.fields) mergedAt } } } }
            """, ["q": "is:pr is:merged author:@me merged:\(after)..\(before)"])
        return try Self.merged(from: data, on: day, calendar: calendar)
    }

    public func reviewedMRs(on day: String) async throws -> [RingItem] {
        guard let from = LocalDay.start(day, calendar: calendar),
              let next = LocalDay.adding(1, to: day, calendar: calendar),
              let to = LocalDay.start(next, calendar: calendar) else { return [] }
        // ponytail: only the latest 100 conversation comments are checked, so comment-only reviews on
        // days far back in a busy account can be missed. Page issueComments if backfill needs them.
        let data = try await query("""
            query($from: DateTime!, $to: DateTime!) { viewer { login
              contributionsCollection(from: $from, to: $to) {
                pullRequestReviewContributions(first: 100) { nodes { occurredAt pullRequest { \(PR.fields) } } } }
              issueComments(last: 100) { nodes { createdAt pullRequest { \(PR.fields) } } } } }
            """, ["from": from.formatted(.iso8601), "to": to.formatted(.iso8601)])
        return try Self.reviewed(from: data, on: day, calendar: calendar)
    }

    // MARK: Parsing, kept static so recorded fixtures can drive it.

    static func merged(from data: Data, on day: String, calendar: Calendar) throws -> [RingItem] {
        struct Response: Decodable {
            struct Search: Decodable { let nodes: [PR] }
            let search: Search
        }
        return try decode(Response.self, from: data).search.nodes
            .filter { $0.mergedAt.map { LocalDay.string($0, calendar: calendar) } == day }
            .map { pr in
                var item = pr.item
                item.date = pr.mergedAt
                return item
            }
    }

    /// One entry per teammate's PR you reviewed or commented on that day, in first-touched order.
    static func reviewed(from data: Data, on day: String, calendar: Calendar) throws -> [RingItem] {
        struct Response: Decodable {
            struct Viewer: Decodable {
                struct Review: Decodable { let occurredAt: Date; let pullRequest: PR }
                struct Comment: Decodable { let createdAt: Date; let pullRequest: PR? }
                struct Contributions: Decodable { let pullRequestReviewContributions: GraphQLNodes<Review> }
                let login: String
                let contributionsCollection: Contributions
                let issueComments: GraphQLNodes<Comment>
            }
            let viewer: Viewer
        }
        let viewer = try decode(Response.self, from: data).viewer
        let touches = viewer.contributionsCollection.pullRequestReviewContributions.nodes.map { ($0.occurredAt, $0.pullRequest) }
            + viewer.issueComments.nodes.compactMap { c in c.pullRequest.map { (c.createdAt, $0) } }
        var seen = Set<URL>()
        return touches
            .filter { LocalDay.string($0.0, calendar: calendar) == day && $0.1.author?.login != viewer.login }
            .sorted { $0.0 < $1.0 }
            .compactMap { date, pr in
                guard seen.insert(pr.url).inserted else { return nil }
                var item = pr.item
                item.date = date
                return item
            }
    }

    /// GraphQL reports most failures in the body of a 200 response.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let envelope = try JSONDecoder.api.decode(GraphQLEnvelope<T>.self, from: data)
        guard let result = envelope.data else { throw GitHubError.query(envelope.errors?.first?.message ?? "no data") }
        return result
    }

    // MARK: Network

    private func query(_ query: String, _ variables: [String: String] = [:]) async throws -> Data {
        try await HTTP(provider: "GitHub", headers: ["Authorization": "Bearer \(credentials.token)"])
            .post(credentials.graphQL, json: ["query": query, "variables": variables])
    }
}

private struct GraphQLEnvelope<T: Decodable>: Decodable {
    struct Message: Decodable { let message: String }
    let data: T?
    let errors: [Message]?
}

private struct GraphQLNodes<T: Decodable>: Decodable { let nodes: [T] }

struct PR: Decodable, Sendable {
    static let fields = "title url number author { login } repository { nameWithOwner }"

    struct Author: Decodable, Sendable {
        let login: String
        let name: String?
        let avatarUrl: URL?
    }
    struct Repository: Decodable, Sendable { let nameWithOwner: String }
    let title: String
    let url: URL
    let number: Int
    let author: Author?
    let repository: Repository
    let mergedAt: Date?

    var item: RingItem {
        RingItem(ref: "\(repository.nameWithOwner)#\(number)", title: title, url: url, project: repository.nameWithOwner)
    }
}

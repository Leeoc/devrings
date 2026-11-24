import Foundation

public struct GitLabCredentials: Codable, Sendable, Equatable {
    public var host: URL
    /// A personal access token, or an OAuth access token when `refreshToken` is set.
    public var token: String
    public var refreshToken: String?
    public var expiresAt: Date?
    var codeVerifier: String?

    public init(host: URL = URL(string: "https://gitlab.com")!, token: String, refreshToken: String? = nil, expiresAt: Date? = nil) {
        self.host = host
        self.token = token
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    public var isOAuth: Bool { refreshToken != nil }

    var headers: [String: String] { isOAuth ? ["Authorization": "Bearer \(token)"] : ["PRIVATE-TOKEN": token] }
}

public actor GitLab: CodeHost {
    private let api: URL
    private var credentials: GitLabCredentials
    private let onRefresh: @Sendable (GitLabCredentials) -> Void
    private var refreshing: Task<GitLabCredentials, any Error>?
    private let calendar: Calendar
    private var user: MR.Author?
    private var mrCache: [MRKey: MR] = [:]

    /// `onRefresh` receives new OAuth tokens; store them, because GitLab invalidates the old refresh token.
    public init(_ credentials: GitLabCredentials, calendar: Calendar = .current,
                onRefresh: @escaping @Sendable (GitLabCredentials) -> Void = { _ in }) {
        api = credentials.host.appending(path: "api/v4")
        self.credentials = credentials
        self.onRefresh = onRefresh
        self.calendar = calendar
    }

    public func account() async throws -> AccountInfo {
        let user = try await me()
        return AccountInfo(name: user.name ?? user.username, handle: "@\(user.username)", avatar: user.avatar_url)
    }

    public var currentCredentials: GitLabCredentials { credentials }

    public func mergedMRs(on day: String) async throws -> [RingItem] {
        guard let start = LocalDay.start(day, calendar: calendar) else { return [] }
        let data = try await getAll("merge_requests", [
            "scope": "created_by_me", "state": "merged",
            "updated_after": start.formatted(.iso8601),
        ])
        return try Self.merged(from: data, on: day, calendar: calendar)
    }

    public func reviewedMRs(on day: String) async throws -> [RingItem] {
        // after/before are exclusive UTC dates and a local day can spill into the UTC days either side.
        guard let after = LocalDay.adding(-2, to: day, calendar: calendar),
              let before = LocalDay.adding(2, to: day, calendar: calendar) else { return [] }
        let data = try await getAll("events", ["after": after, "before": before])
        let myID = try await me().id
        var items: [RingItem] = []
        for touch in try Self.reviewedMRs(from: data, on: day, calendar: calendar) {
            let mr = try await mergeRequest(touch.key)
            guard mr.author.id != myID else { continue }
            var item = mr.item
            item.date = touch.date
            items.append(item)
        }
        return items
    }

    // MARK: Parsing, kept static so recorded fixtures can drive it.

    static func merged(from pages: [Data], on day: String, calendar: Calendar) throws -> [RingItem] {
        try pages.flatMap { try JSONDecoder.api.decode([MR].self, from: $0) }
            .filter { $0.merged_at.map { LocalDay.string($0, calendar: calendar) } == day }
            .map { mr in
                var item = mr.item
                item.date = mr.merged_at
                return item
            }
    }

    /// One entry per MR you commented on, approved or merged that day, in first-touched order.
    /// Request changes has no event of its own; it arrives as the review's comments.
    static func reviewedMRs(from pages: [Data], on day: String, calendar: Calendar) throws -> [ReviewTouch] {
        let events = try pages.flatMap { try JSONDecoder.api.decode([Event].self, from: $0) }
            .filter { LocalDay.string($0.created_at, calendar: calendar) == day }
            .sorted { $0.created_at < $1.created_at }
        var seen = Set<MRKey>()
        return events.compactMap { e -> ReviewTouch? in
            let iid: Int? = switch e.action_name {
            case "approved", "accepted": e.target_type == "MergeRequest" ? e.target_iid : nil
            case "commented on": e.note?.noteable_type == "MergeRequest" ? e.note?.noteable_iid : nil
            default: nil
            }
            guard let iid else { return nil }
            let key = MRKey(project: e.project_id, iid: iid)
            return seen.insert(key).inserted ? ReviewTouch(key: key, date: e.created_at) : nil
        }
    }

    // MARK: Network

    private func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        if let expiry = credentials.expiresAt, expiry < .now.addingTimeInterval(60) { try await refresh() }
        do {
            return try await HTTP(provider: "GitLab", headers: credentials.headers).get(url)
        } catch ProviderError.unauthorized(_) where credentials.isOAuth {
            try await refresh()
            return try await HTTP(provider: "GitLab", headers: credentials.headers).get(url)
        }
    }

    /// Concurrent requests share one refresh, since each refresh token only works once.
    private func refresh() async throws {
        if let refreshing {
            credentials = try await refreshing.value
            return
        }
        let current = credentials
        let task = Task { try await GitLabOAuth.refresh(current) }
        refreshing = task
        defer { refreshing = nil }
        credentials = try await task.value
        onRefresh(credentials)
    }

    private func me() async throws -> MR.Author {
        if let user { return user }
        let fetched = try JSONDecoder.api.decode(MR.Author.self, from: try await get(api.appending(path: "user")).0)
        user = fetched
        return fetched
    }

    private func mergeRequest(_ key: MRKey) async throws -> MR {
        if let cached = mrCache[key] { return cached }
        let url = api.appending(path: "projects/\(key.project)/merge_requests/\(key.iid)")
        let mr = try JSONDecoder.api.decode(MR.self, from: try await get(url).0)
        mrCache[key] = mr
        return mr
    }

    private func getAll(_ path: String, _ query: [String: String]) async throws -> [Data] {
        var pages: [Data] = []
        var page = "1"
        while !page.isEmpty {
            let items = query.merging(["per_page": "100", "page": page]) { $1 }.map { URLQueryItem(name: $0, value: $1) }
            let (data, response) = try await get(api.appending(path: path).appending(queryItems: items))
            pages.append(data)
            page = response.value(forHTTPHeaderField: "x-next-page") ?? ""
        }
        return pages
    }
}

struct ReviewTouch: Equatable, Sendable {
    let key: MRKey
    let date: Date
}

struct MRKey: Hashable, Sendable {
    let project: Int
    let iid: Int
}

struct MR: Decodable, Sendable {
    struct Author: Decodable, Sendable {
        let id: Int
        let username: String
        let name: String?
        let avatar_url: URL?
    }
    struct References: Decodable, Sendable {
        let full: String
    }
    let title: String
    let web_url: URL
    let merged_at: Date?
    let references: References
    let author: Author

    var item: RingItem {
        RingItem(ref: references.full, title: title, url: web_url,
                 project: references.full.split(separator: "!").first.map(String.init))
    }
}

struct Event: Decodable, Sendable {
    struct Note: Decodable, Sendable {
        let noteable_type: String?
        let noteable_iid: Int?
    }
    let action_name: String
    let project_id: Int
    let target_iid: Int?
    let target_type: String?
    let created_at: Date
    let note: Note?
}

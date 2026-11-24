import Foundation

public struct JiraCredentials: Codable, Sendable, Equatable {
    public var site: URL
    public var email: String
    public var token: String
    /// Set for scoped API tokens, which only work through Atlassian's gateway, not the site's own address.
    public var apiBase: URL?

    public init(site: URL, email: String, token: String, apiBase: URL? = nil) {
        self.site = site
        self.email = email
        self.token = token
        self.apiBase = apiBase
    }

    /// Accepts "your-team", "your-team.atlassian.net" or a full URL, and returns the site's https address.
    public static func site(from input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let host = URLComponents(string: text)?.host, !host.isEmpty,
              host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." }) else { return nil }
        return URL(string: "https://" + (host.contains(".") ? host : host + ".atlassian.net"))
    }
}

public enum JiraConnectError: LocalizedError, Equatable {
    case siteNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .siteNotFound(let site): "Couldn't find an Atlassian site at \(site)."
        }
    }
}

public struct Jira: WorkTracker {
    private let site: URL
    private let apiBase: URL
    private let http: HTTP
    private let calendar: Calendar

    public init(_ credentials: JiraCredentials, calendar: Calendar = .current) {
        site = credentials.site
        apiBase = credentials.apiBase ?? credentials.site.appending(path: "rest/api/3")
        let basic = Data("\(credentials.email):\(credentials.token)".utf8).base64EncodedString()
        http = HTTP(provider: "Jira", headers: ["Authorization": "Basic \(basic)"])
        self.calendar = calendar
    }

    /// Checks the details work, trying the site's own API first (classic tokens) and then Atlassian's
    /// gateway (scoped tokens). Returns credentials for whichever worked.
    public static func connect(site: URL, email: String, token: String) async throws -> (JiraCredentials, AccountInfo) {
        let classic = JiraCredentials(site: site, email: email, token: token)
        do {
            return (classic, try await Jira(classic).account())
        } catch ProviderError.unauthorized(_) {
            let scoped = JiraCredentials(site: site, email: email, token: token, apiBase: try await gateway(for: site))
            return (scoped, try await Jira(scoped).account())
        } catch let error as URLError where [.cannotFindHost, .dnsLookupFailed].contains(error.code) {
            throw JiraConnectError.siteNotFound(site.host() ?? site.absoluteString)
        } catch ProviderError.http(404, _) {
            throw JiraConnectError.siteNotFound(site.host() ?? site.absoluteString)
        }
    }

    /// Whether `site` is a Jira Cloud site, via Atlassian's public tenant lookup. No credentials needed.
    public static func siteExists(_ site: URL) async -> Bool {
        (try? await gateway(for: site)) != nil
    }

    private static func gateway(for site: URL) async throws -> URL {
        struct Tenant: Decodable { let cloudId: String }
        let data = try await HTTP(provider: "Jira", headers: [:]).get(site.appending(path: "_edge/tenant_info")).0
        return gatewayBase(cloudID: try JSONDecoder().decode(Tenant.self, from: data).cloudId)
    }

    static func gatewayBase(cloudID: String) -> URL {
        URL(string: "https://api.atlassian.com/ex/jira/\(cloudID)/rest/api/3")!
    }

    public func account() async throws -> AccountInfo {
        struct Myself: Decodable {
            let displayName: String
            let emailAddress: String?
            let avatarUrls: [String: URL]?
        }
        let me = try JSONDecoder().decode(Myself.self, from: try await http.get(api("myself")).0)
        return AccountInfo(name: me.displayName, handle: me.emailAddress, avatar: me.avatarUrls?["48x48"])
    }

    public func ticketsMoved(on day: String, matching filter: TicketFilter) async throws -> [RingItem] {
        guard let jql = Self.movedJQL(on: day, matching: filter, calendar: calendar) else { return [] }
        return try await search(jql).map { $0.item(site: site) }
    }

    public func labels() async throws -> [String] {
        struct Page: Decodable { let values: [String]; let isLast: Bool }
        var labels: [String] = [], start = 0
        while true {
            let url = api("label").appending(queryItems: [.init(name: "startAt", value: "\(start)"), .init(name: "maxResults", value: "1000")])
            let page = try JSONDecoder().decode(Page.self, from: try await http.get(url).0)
            labels += page.values
            start += page.values.count
            if page.isLast || page.values.isEmpty { return labels }
        }
    }

    public func projects() async throws -> [TrackerOption] {
        struct Page: Decodable { let values: [TrackerOption]; let isLast: Bool }
        var projects: [TrackerOption] = [], start = 0
        while true {
            let url = api("project/search").appending(queryItems: [.init(name: "startAt", value: "\(start)"), .init(name: "maxResults", value: "100")])
            let page = try JSONDecoder().decode(Page.self, from: try await http.get(url).0)
            projects += page.values
            start += page.values.count
            if page.isLast || page.values.isEmpty { return projects }
        }
    }

    public func epics(inProject project: String?) async throws -> [TrackerOption] {
        var jql = "issuetype = Epic AND statusCategory != Done"
        if let project { jql += " AND " + (TicketFilter(project: project).jql ?? "") }
        return try await search(jql + " ORDER BY updated DESC").map { TrackerOption(key: $0.key, name: $0.fields.summary) }
    }

    // MARK: Parsing, kept static so recorded fixtures can drive it.

    static func movedJQL(on day: String, matching filter: TicketFilter, calendar: Calendar) -> String? {
        guard let next = LocalDay.adding(1, to: day, calendar: calendar) else { return nil }
        let moved = "status CHANGED BY currentUser() DURING (\"\(day)\", \"\(next)\")"
        return filter.jql.map { "\(moved) AND (\($0))" } ?? moved
    }

    static func searchPage(from data: Data) throws -> SearchPage {
        try JSONDecoder().decode(SearchPage.self, from: data)
    }

    // MARK: Network

    private func api(_ path: String) -> URL {
        apiBase.appending(path: path)
    }

    private func search(_ jql: String) async throws -> [Issue] {
        var issues: [Issue] = []
        var token: String?
        repeat {
            var body: [String: any Sendable] = ["jql": jql, "fields": ["summary", "status", "project"], "maxResults": 100]
            if let token { body["nextPageToken"] = token }
            let page = try Self.searchPage(from: try await http.post(api("search/jql"), json: body))
            issues += page.issues
            token = page.isLast == false ? page.nextPageToken : nil
        } while token != nil
        return issues
    }
}

struct SearchPage: Decodable {
    let issues: [Issue]
    let nextPageToken: String?
    let isLast: Bool?
}

struct Issue: Decodable {
    struct Named: Decodable { let name: String }
    struct Fields: Decodable {
        let summary: String
        let status: Named?
        let project: Named?
    }
    let key: String
    let fields: Fields

    func item(site: URL) -> RingItem {
        RingItem(ref: key, title: fields.summary, url: site.appending(path: "browse/\(key)"),
                 project: fields.project?.name, status: fields.status?.name)
    }
}

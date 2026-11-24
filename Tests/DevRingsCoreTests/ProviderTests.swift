import Foundation
import Testing
@testable import DevRingsCore

// London in July is UTC+1, so 23:xxZ belongs to the next local day.
private let london: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/London")!
    return c
}()

private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/\(name)"))
}

@Test func mergedKeepsOnlyMRsMergedOnTheLocalDay() throws {
    let items = try GitLab.merged(from: [fixture("gitlab-merged.json")], on: "2026-07-14", calendar: london)
    #expect(items.map(\.ref) == ["acme/app!41", "acme/app!40"])
    #expect(items[0].project == "acme/app")
    #expect(items[0].shortRef == "!41")
    #expect(items[0].date != nil)
    #expect(items[0].url.absoluteString == "https://gitlab.com/acme/app/-/merge_requests/41")
}

@Test func reviewCountsEachMROncePerDayAcrossPages() throws {
    let pages = try [fixture("gitlab-events-1.json"), fixture("gitlab-events-2.json")]
    let touches = try GitLab.reviewedMRs(from: pages, on: "2026-07-14", calendar: london)
    #expect(touches.first?.date == Date(timeIntervalSince1970: 1_783_984_200))
    #expect(touches.map(\.key) == [MRKey(project: 1, iid: 30), MRKey(project: 2, iid: 10), MRKey(project: 1, iid: 10), MRKey(project: 2, iid: 22)])
}

@Test func mrDetailDecodesAuthorForOwnMRExclusion() throws {
    let mr = try JSONDecoder.api.decode(MR.self, from: fixture("gitlab-mr.json"))
    #expect(mr.author.id == 8)
    #expect(mr.item.title == "Network policies")
}

@Test func gitHubMergedKeepsOnlyPRsMergedOnTheLocalDay() throws {
    let items = try GitHub.merged(from: fixture("github-merged.json"), on: "2026-07-14", calendar: london)
    #expect(items.map(\.ref) == ["acme/app#41", "acme/api#7"])
    #expect(items[0].shortRef == "#41")
    #expect(items[0].project == "acme/app")
    #expect(items[0].date != nil)
}

@Test func gitHubReviewCountsTeammatesPRsOncePerDay() throws {
    let items = try GitHub.reviewed(from: fixture("github-reviewed.json"), on: "2026-07-14", calendar: london)
    #expect(items.map(\.ref) == ["acme/api#9", "acme/app#50", "acme/web#3"])
    #expect(items.first?.date == Date(timeIntervalSince1970: 1_784_016_000))
}

@Test func gitHubQueryErrorsSurface() {
    #expect(throws: GitHubError.query("Bad credentials")) {
        try GitHub.decode(String.self, from: Data(#"{"data":null,"errors":[{"message":"Bad credentials"}]}"#.utf8))
    }
    #expect(GitHubCredentials(token: "t").graphQL.absoluteString == "https://api.github.com/graphql")
    #expect(GitHubCredentials(host: URL(string: "https://ghe.acme.com")!, token: "t").graphQL.absoluteString == "https://ghe.acme.com/api/graphql")
}

@Test func jiraSearchPageParsesItemsAndNextToken() throws {
    let page = try Jira.searchPage(from: fixture("jira-search.json"))
    let site = URL(string: "https://acme.atlassian.net")!
    #expect(page.issues.map { $0.item(site: site).url.absoluteString } == [
        "https://acme.atlassian.net/browse/ABC-12", "https://acme.atlassian.net/browse/ABC-15",
    ])
    #expect(page.issues[1].item(site: site).status == "In Review")
    #expect(page.issues[0].item(site: site).project == "Acme")
    #expect(page.issues[0].item(site: site).shortRef == "ABC-12")
    #expect(page.nextPageToken == "CAEaAggD")
    #expect(page.isLast == false)
}

@Test func movedJQLWrapsTheFilter() {
    let filter = TicketFilter(labels: ["tech-debt"])
    #expect(Jira.movedJQL(on: "2026-07-31", matching: filter, calendar: london)
        == #"status CHANGED BY currentUser() DURING ("2026-07-31", "2026-08-01") AND (labels in ("tech-debt"))"#)
    #expect(Jira.movedJQL(on: "2026-07-31", matching: TicketFilter(), calendar: london)
        == #"status CHANGED BY currentUser() DURING ("2026-07-31", "2026-08-01")"#)
}

@Test func ticketFilterBuildsJQL() {
    #expect(TicketFilter().jql == nil)
    #expect(TicketFilter(labels: ["a", "b"]).jql == #"labels in ("a", "b")"#)
    #expect(TicketFilter(labels: ["a", "b"], matchAllLabels: true).jql == #"labels = "a" AND labels = "b""#)
    #expect(TicketFilter(labels: ["a"], project: "ABC", epic: "ABC-1").jql
        == #"labels in ("a") AND project = "ABC" AND parent = "ABC-1""#)
    #expect(TicketFilter(labels: ["a"], rawJQL: "  priority = High ").jql == "priority = High")
    #expect(TicketFilter(labels: [#"we"ird"#]).jql == #"labels in ("we\"ird")"#)
}

private struct FakeHost: CodeHost {
    var reviewFails = false
    func account() async throws -> AccountInfo { AccountInfo(name: "Dev") }
    func mergedMRs(on day: String) async throws -> [RingItem] {
        [RingItem(ref: "!1", title: "New", url: URL(string: "https://x")!)]
    }
    func reviewedMRs(on day: String) async throws -> [RingItem] {
        if reviewFails { throw ProviderError.http(500, "GitLab") }
        return []
    }
}

@Test func failedRingKeepsPreviousItemsAndReportsOnce() async {
    let setup = RingSetup()
    var previous = setup.emptyRecord(for: "2026-07-14")
    previous.rings[1].items = [RingItem(ref: "!9", title: "Earlier", url: URL(string: "https://x")!)]
    let (record, errors) = await Refresher.record(for: "2026-07-14", setup: setup, previous: previous,
                                                  codeHosts: [FakeHost(reviewFails: true)], tracker: nil)
    #expect(record.rings.map(\.count) == [1, 1])
    #expect(record.rings[1].items[0].ref == "!9")
    #expect(errors == ["GitLab returned an error (500)."])
}

@Test func ticketKeysFoundInTitles() {
    #expect(TicketKeys.find(in: ":sparkles: (PAY-42) add job, see PAY-42 and ABC-7") == ["PAY-42", "ABC-7"])
    #expect(TicketKeys.find(in: "Parse UTF-8 for PAY-1", projects: ["PAY"]) == ["PAY-1"])
    #expect(TicketKeys.find(in: "no keys here") == [])
}

@Test func displayTitleDropsGitmojiAndLinkedKeys() {
    func title(_ t: String, _ keys: [String] = []) -> String {
        RingItem(ref: "", title: t, url: URL(string: "https://x")!).displayTitle(hiding: keys)
    }
    #expect(title(":sparkles: (PAY-42) add provision job", ["PAY-42"]) == "add provision job")
    #expect(title(":sparkles: (PAY-42) add provision job") == "(PAY-42) add provision job")
    #expect(title("🐛 WEB-1047: search filters", ["WEB-1047"]) == "🐛 search filters")
    #expect(title("Draft: :bug: (PAY-1) fix", ["PAY-1"]) == "Draft: fix")
    #expect(title("(PAY-1)", ["PAY-1"]) == "(PAY-1)")
    #expect(title("Plain title") == "Plain title")
}

@Test func pkceChallengeMatchesSHA256OfTheVerifier() {
    // Expected value computed independently with Python's hashlib.
    #expect(GitLabOAuth.challenge(for: "dBjftJeZ4CVP-mJ92K1RW-5Bf43_tVa3WNCcPCOB-g") == "Tp1z-npv-CiVcOoTT1DD4BkIhvVp_CIRYid29XjfXFM")
    #expect(GitLabOAuth.random().count == 43)
    #expect(GitLabOAuth.random() != GitLabOAuth.random())
}

@Test func authorizeURLCarriesPKCEAndState() {
    let request = GitLabOAuth.request(verifier: "v", state: "s")
    let items = URLComponents(url: request.url, resolvingAgainstBaseURL: false)!.queryItems!
    func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
    #expect(request.url.path() == "/oauth/authorize")
    #expect(value("code_challenge_method") == "S256")
    #expect(value("code_challenge") == GitLabOAuth.challenge(for: "v"))
    #expect(value("state") == "s")
    #expect(value("redirect_uri") == "devrings://oauth")
    #expect(value("scope") == "read_api")
}

@Test func callbackParsingChecksStateAndErrors() throws {
    #expect(try GitLabOAuth.code(from: URL(string: "devrings://oauth?code=abc&state=s")!, state: "s") == "abc")
    #expect(throws: SignInError.stateMismatch) { try GitLabOAuth.code(from: URL(string: "devrings://oauth?code=abc&state=x")!, state: "s") }
    #expect(throws: SignInError.denied("The user denied access")) {
        try GitLabOAuth.code(from: URL(string: "devrings://oauth?error=access_denied&error_description=The%20user%20denied%20access&state=s")!, state: "s")
    }
    #expect(throws: SignInError.missingCode) { try GitLabOAuth.code(from: URL(string: "devrings://oauth?state=s")!, state: "s") }
}

@Test func tokenResponseBecomesOAuthCredentials() throws {
    let json = #"{"access_token":"at","token_type":"Bearer","expires_in":7200,"refresh_token":"rt","scope":"read_api","created_at":1800000000}"#
    let credentials = try GitLabOAuth.credentials(from: Data(json.utf8))
    #expect(credentials.isOAuth)
    #expect(credentials.headers == ["Authorization": "Bearer at"])
    #expect(credentials.expiresAt == Date(timeIntervalSince1970: 1_800_007_200))
    #expect(GitLabCredentials(token: "pat").headers == ["PRIVATE-TOKEN": "pat"])
}

@Test func storedTokenCredentialsStillDecode() throws {
    let old = #"{"host":"https://gitlab.com","token":"pat"}"#
    let decoded = try JSONDecoder().decode(GitLabCredentials.self, from: Data(old.utf8))
    #expect(!decoded.isOAuth)
    let jira = try JSONDecoder().decode(JiraCredentials.self, from: Data(#"{"site":"https://a.atlassian.net","email":"e","token":"t"}"#.utf8))
    #expect(jira.apiBase == nil)
}

@Test func jiraSiteAcceptsShortAndFullForms() {
    #expect(JiraCredentials.site(from: "acme")?.absoluteString == "https://acme.atlassian.net")
    #expect(JiraCredentials.site(from: " Acme.atlassian.net ")?.absoluteString == "https://acme.atlassian.net")
    #expect(JiraCredentials.site(from: "https://acme.atlassian.net/jira/your-work")?.absoluteString == "https://acme.atlassian.net")
    #expect(JiraCredentials.site(from: "jira.example.com")?.absoluteString == "https://jira.example.com")
    #expect(JiraCredentials.site(from: "") == nil)
    #expect(JiraCredentials.site(from: "not a site") == nil)
    #expect(Jira.gatewayBase(cloudID: "abc").absoluteString == "https://api.atlassian.com/ex/jira/abc/rest/api/3")
}

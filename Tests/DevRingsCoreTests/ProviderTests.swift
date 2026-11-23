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
    func username() async throws -> String { "dev" }
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
                                                  codeHost: FakeHost(reviewFails: true), tracker: nil)
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

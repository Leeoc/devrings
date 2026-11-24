import AppKit
import DevRingsCore
import Foundation
import Observation

struct ItemLink: Hashable, Identifiable {
    let label: String
    let symbol: String
    let url: URL
    var id: URL { url }
}

enum Pane: String, Hashable {
    case history, trends, awards, rings, accounts, timeOff, general
}

@MainActor @Observable
final class AppModel {
    var days: [String: DayRecord] = [:]
    var settings = Settings() {
        didSet { settingsChanged(from: oldValue) }
    }
    var lastRefresh: Date?
    var availableUpdate: AvailableUpdate?
    private var lastUpdateCheck: Date?
    var errors: [String] = []
    var isRefreshing = false
    var backfillRemaining = 0
    var pane: Pane = .history

    private(set) var gitLab: (any CodeHost)?
    private(set) var gitHub: GitHub?
    var codeHosts: [any CodeHost] { [gitLab, gitHub].compactMap { $0 } }
    private(set) var tracker: (any WorkTracker)?
    var gitLabAccount: AccountInfo?
    private(set) var gitLabUsesOAuth = false
    var gitHubAccount: AccountInfo?
    private(set) var gitHubSignedIn = false
    var jiraAccount: AccountInfo?
    /// What's needed to show and replace the Jira connection, without keeping the token in memory here.
    private(set) var jiraConnection: (email: String, usesScopedToken: Bool)?
    private(set) var jiraSite: URL?
    private var projectKeys: Set<String>?

    private var labelsCache: [String]?
    private var projectsCache: [TrackerOption]?
    private var refreshAgain = false
    private var pendingRefresh: Task<Void, Never>?
    let isFixture = CommandLine.arguments.contains("--fixture")
    let notifier = Notifier()
    /// Set by the app delegate, so settings can reopen the welcome window.
    var showOnboarding: () -> Void = {}

    static let historyDays = 365
    static let backfillDays = 30

    init() {
        if isFixture {
            (days, settings) = Fixtures.history()
            jiraSite = Fixtures.jiraSite
            projectKeys = ["ABC"]
        } else {
            days = Storage.load([String: DayRecord].self, from: "history.json") ?? [:]
            settings = Storage.load(Settings.self, from: "settings.json") ?? Settings()
        }
    }

    var todayKey: String { LocalDay.string(.now) }
    var today: DayRecord { days[todayKey] ?? settings.setup.emptyRecord(for: todayKey) }
    var history: History { History(days: days, settings: settings, today: todayKey) }

    func start() {
        guard !isFixture else { return }
        let gitLab = Keychain.load(GitLabCredentials.self, account: "gitlab")
        self.gitLab = gitLab.map(Self.gitLab)
        let gitHubCredentials = Keychain.load(GitHubCredentials.self, account: "github")
        gitHub = gitHubCredentials.map { GitHub($0) }
        gitHubSignedIn = gitHubCredentials?.signedIn == true
        gitLabUsesOAuth = gitLab?.isOAuth ?? false
        let jira = Keychain.load(JiraCredentials.self, account: "jira")
        tracker = jira.map { Jira($0) }
        jiraSite = jira?.site
        jiraConnection = jira.map { ($0.email, $0.apiBase != nil) }
        Task { await loadAccounts() }
        Task {
            await refresh()
            await backfill()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(600))
                await refresh()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    // MARK: Refreshing

    /// Opening the menu refreshes too, but not more than once a minute.
    func refreshIfStale() {
        guard !isFixture, lastRefresh.map({ Date.now.timeIntervalSince($0) > 60 }) ?? true else { return }
        Task { await refresh() }
    }

    func refresh() async {
        guard !isFixture else { return }
        guard !isRefreshing else {
            refreshAgain = true
            return
        }
        isRefreshing = true
        repeat {
            refreshAgain = false
            let day = todayKey
            let (record, errors) = await Refresher.record(for: day, setup: settings.setup, previous: days[day],
                                                          codeHosts: codeHosts, tracker: tracker)
            days[day] = record
            self.errors = errors + missingAccounts
            if errors.isEmpty { lastRefresh = .now }
        } while refreshAgain
        isRefreshing = false
        saveHistory()
        await checkForUpdateDaily()
        notifier.check(history)
    }

    /// Fills in recent working days the app has never seen, so history isn't empty on day one.
    /// `refetch` redoes days already recorded too, for when a newly connected account adds to them.
    func backfill(refetch: Bool = false) async {
        guard !codeHosts.isEmpty else { return }
        let missing = (1...Self.backfillDays).compactMap { LocalDay.adding(-$0, to: todayKey) }
            .filter { history.isWorkingDay($0) && (refetch || days[$0] == nil) }
        backfillRemaining = missing.count
        for day in missing {
            var (record, errors) = await Refresher.record(for: day, setup: settings.setup, previous: days[day],
                                                          codeHosts: codeHosts, tracker: tracker)
            guard errors.isEmpty else { break }
            if let recorded = days[day] {
                record.rings = recorded.rings.map { ring in
                    var ring = ring
                    ring.items = record.rings.first { $0.id == ring.id }?.items ?? ring.items
                    return ring
                }
            }
            days[day] = record
            backfillRemaining -= 1
        }
        backfillRemaining = 0
        saveHistory()
    }

    private var missingAccounts: [String] {
        (codeHosts.isEmpty ? ["Connect GitLab or GitHub in Settings › Accounts."] : [])
            + (tracker == nil && settings.setup.ticket != nil ? ["Jira isn't connected."] : [])
    }

    // MARK: Updates

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private func checkForUpdateDaily() async {
        guard settings.checkForUpdates else {
            availableUpdate = nil
            return
        }
        guard lastUpdateCheck.map({ Date.now.timeIntervalSince($0) > 86_400 }) ?? true else { return }
        lastUpdateCheck = .now
        // Fails quietly: no network, or no public release yet.
        availableUpdate = try? await Updates.check(current: Self.currentVersion)
    }

    // MARK: Today

    func togglePauseToday() {
        var record = today
        record.pause = record.pause == nil ? .manual : nil
        days[todayKey] = record
        saveHistory()
    }

    // MARK: Settings and persistence

    private func settingsChanged(from old: Settings) {
        guard !isFixture else { return }
        try? Storage.save(settings, to: "settings.json")
        guard old.setup != settings.setup else { return }
        applySetupToToday()
        if old.setup.ticket?.filter != settings.setup.ticket?.filter || old.setup.ticket?.id != settings.setup.ticket?.id {
            pendingRefresh?.cancel()
            pendingRefresh = Task {
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled { await refresh() }
            }
        }
    }

    /// Goals and names change at once; past days keep the setup they were recorded with.
    private func applySetupToToday() {
        let current = today
        var record = settings.setup.emptyRecord(for: todayKey)
        record.pause = current.pause
        record.rings = record.rings.map { ring in
            var ring = ring
            ring.items = current.rings.first { $0.id == ring.id }?.items ?? []
            return ring
        }
        days[todayKey] = record
    }

    private func saveHistory() {
        guard !isFixture else { return }
        let cutoff = LocalDay.adding(-Self.historyDays, to: todayKey) ?? ""
        days = days.filter { $0.key >= cutoff }
        try? Storage.save(days, to: "history.json")
    }

    // MARK: Accounts

    /// Opens GitLab's sign-in page in a secure browser sheet, then connects with the tokens it returns.
    func signInWithGitLab() async throws {
        let request = GitLabOAuth.request()
        let callback = try await WebSignIn().callback(for: request.url, scheme: GitLabOAuth.callbackScheme)
        try await connectGitLab(try await GitLabOAuth.signIn(request, callback: callback))
    }

    func connectGitLab(_ credentials: GitLabCredentials) async throws {
        let host = Self.gitLab(credentials)
        gitLabAccount = try await host.account()
        try Keychain.save(credentials, account: "gitlab")
        gitLab = host
        gitLabUsesOAuth = credentials.isOAuth
        await refresh()
        await backfill(refetch: true)
    }

    func disconnectGitLab() {
        if let host = gitLab as? GitLab {
            Task { await GitLabOAuth.revoke(await host.currentCredentials) }
        }
        Keychain.delete(account: "gitlab")
        gitLab = nil
        gitLabAccount = nil
        gitLabUsesOAuth = false
    }

    func connectGitHub(_ credentials: GitHubCredentials) async throws {
        let host = GitHub(credentials)
        gitHubAccount = try await host.account()
        try Keychain.save(credentials, account: "github")
        gitHub = host
        gitHubSignedIn = credentials.signedIn == true
        await refresh()
        await backfill(refetch: true)
    }

    func disconnectGitHub() {
        Keychain.delete(account: "github")
        gitHub = nil
        gitHubAccount = nil
        gitHubSignedIn = false
    }

    func connectJira(site: URL, email: String, token: String) async throws {
        let (credentials, account) = try await Jira.connect(site: site, email: email, token: token)
        try Keychain.save(credentials, account: "jira")
        jiraAccount = account
        tracker = Jira(credentials)
        jiraSite = credentials.site
        jiraConnection = (credentials.email, credentials.apiBase != nil)
        labelsCache = nil
        projectsCache = nil
        projectKeys = nil
        await refresh()
    }

    /// Swaps in a new token for the same site and email, for when the old one expires.
    func replaceJiraToken(_ token: String) async throws {
        guard let site = jiraSite, let email = jiraConnection?.email else { return }
        try await connectJira(site: site, email: email, token: token)
    }

    func disconnectJira() {
        Keychain.delete(account: "jira")
        tracker = nil
        jiraAccount = nil
        jiraSite = nil
        jiraConnection = nil
    }

    /// OAuth access tokens last two hours; each refresh replaces the stored refresh token, which GitLab
    /// invalidates once it's used.
    private static func gitLab(_ credentials: GitLabCredentials) -> GitLab {
        GitLab(credentials) { refreshed in try? Keychain.save(refreshed, account: "gitlab") }
    }

    private func loadAccounts() async {
        gitLabAccount = try? await gitLab?.account()
        gitHubAccount = try? await gitHub?.account()
        jiraAccount = try? await tracker?.account()
        if tracker != nil, let projects = try? await trackerProjects() { projectKeys = Set(projects.map(\.key)) }
    }

    // MARK: Links between MRs and tickets

    /// Tickets an MR's title mentions, or MRs anywhere in history that mention a ticket.
    func links(for item: RingItem, kind: RingKind) -> [ItemLink] {
        switch kind {
        case .ship, .review:
            guard let jiraSite else { return [] }
            return TicketKeys.find(in: item.title, projects: projectKeys).map {
                ItemLink(label: $0, symbol: "ticket", url: jiraSite.appending(path: "browse/\($0)"))
            }
        case .ticket:
            var seen = Set<URL>()
            return days.values.sorted { $0.date < $1.date }
                .flatMap(\.rings).filter { $0.id.kind != .ticket }.flatMap(\.items)
                .filter { TicketKeys.find(in: $0.title).contains(item.ref) && seen.insert($0.url).inserted }
                .map { ItemLink(label: $0.shortRef, symbol: "arrow.triangle.merge", url: $0.url) }
        }
    }

    // MARK: Ticket ring setup

    func trackerLabels() async throws -> [String] {
        if let labelsCache { return labelsCache }
        let labels = try await tracker?.labels() ?? []
        labelsCache = labels
        return labels
    }

    func trackerProjects() async throws -> [TrackerOption] {
        if let projectsCache { return projectsCache }
        let projects = try await tracker?.projects().sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } ?? []
        projectsCache = projects
        return projects
    }

    func trackerEpics(in project: String?) async throws -> [TrackerOption] {
        try await tracker?.epics(inProject: project) ?? []
    }

    /// Tickets matching `filter` on each of the last 10 working days, oldest first.
    func preview(_ filter: TicketFilter) async throws -> [(day: String, count: Int)] {
        guard let tracker else { return [] }
        let history = history
        var workingDays: [String] = []
        var offset = 1
        while workingDays.count < 10, offset < 60, let day = LocalDay.adding(-offset, to: todayKey) {
            if history.isWorkingDay(day) { workingDays.insert(day, at: 0) }
            offset += 1
        }
        return try await withThrowingTaskGroup(of: (String, Int).self) { group in
            for day in workingDays {
                group.addTask { (day, try await tracker.ticketsMoved(on: day, matching: filter).count) }
            }
            var counts: [String: Int] = [:]
            for try await (day, count) in group { counts[day] = count }
            return workingDays.map { ($0, counts[$0] ?? 0) }
        }
    }
}

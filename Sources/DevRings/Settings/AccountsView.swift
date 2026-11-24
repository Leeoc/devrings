import DevRingsCore
import SwiftUI

struct AccountsView: View {
    let model: AppModel
    var showsCode = true
    var showsTickets = true

    var body: some View {
        Form {
            if (showsCode && (model.gitLab != nil || model.gitHub != nil)) || (showsTickets && model.tracker != nil) {
                Section("Connected") {
                    if showsCode, model.gitLab != nil {
                        AccountRow(provider: "GitLab", account: model.gitLabAccount,
                                   detail: model.gitLabUsesOAuth ? "Signed in" : "Access token", dataUse: .gitLab) {
                            model.disconnectGitLab()
                        }
                    }
                    if showsCode, model.gitHub != nil {
                        AccountRow(provider: "GitHub", account: model.gitHubAccount,
                                   detail: model.gitHubSignedIn ? "Signed in" : "Access token", dataUse: .gitHub) {
                            model.disconnectGitHub()
                        }
                    }
                    if showsTickets, model.tracker != nil { JiraConnected(model: model) }
                }
            }
            if showsCode, model.gitLab == nil || model.gitHub == nil {
                Section {
                    if model.gitLab == nil { GitLabSetup(model: model) }
                    if model.gitHub == nil { GitHubSetup(model: model) }
                } header: {
                    Text("Code")
                } footer: {
                    Text("Fills the Ship and Review rings. Connect one or both; they count toward the same rings.")
                }
            }
            if showsTickets, model.tracker == nil {
                Section {
                    JiraSetup(model: model)
                } header: {
                    Text("Tickets")
                } footer: {
                    Text("Only needed for a ticket ring. Atlassian doesn't offer app sign-in for Jira yet, so DevRings uses an API token.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct GitLabSetup: View {
    let model: AppModel
    @State private var useToken = !GitLabOAuth.isConfigured
    @State private var host = "https://gitlab.com"
    @State private var token = ""
    @State private var error: String?
    @State private var working = false

    var body: some View {
        ProviderSetup(name: "GitLab", summary: "gitlab.com or self-hosted", error: error) {
                if GitLabOAuth.isConfigured {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sign in to gitlab.com")
                            Text("DevRings only asks to read your activity.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if working && !useToken { ProgressView().controlSize(.small) }
                        Button("Sign In with GitLab…", action: signIn)
                            .buttonStyle(.borderedProminent)
                            .disabled(working)
                    }
                }
                DisclosureGroup(GitLabOAuth.isConfigured ? "Use an access token instead" : "Access token", isExpanded: $useToken) {
                    TextField("Server", text: $host)
                    SecureField("Token", text: $token, prompt: Text("glpat-…"))
                    HStack {
                        if let url = tokenPage { Link("Create a Token…", destination: url) }
                        Spacer()
                        if working && useToken { ProgressView().controlSize(.small) }
                        Button("Connect", action: connectWithToken)
                            .disabled(token.isEmpty || working)
                    }
                    Text("For self-hosted GitLab, or if you'd rather not sign in. Needs the read_api scope.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                DataUse(.gitLab)
        }
    }

    private var tokenPage: URL? {
        httpsURL(host)?.appending(path: "-/user_settings/personal_access_tokens")
            .appending(queryItems: [.init(name: "name", value: "DevRings"), .init(name: "scopes", value: "read_api")])
    }

    private func signIn() {
        run {
            do {
                try await model.signInWithGitLab()
            } catch where WebSignIn.wasCancelled(error) {
                return
            }
        }
    }

    private func connectWithToken() {
        guard let server = httpsURL(host) else {
            error = "Enter the server's https:// address."
            return
        }
        run {
            try await model.connectGitLab(GitLabCredentials(host: server, token: token.trimmingCharacters(in: .whitespacesAndNewlines)))
            token = ""
        }
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        working = true
        error = nil
        Task {
            defer { working = false }
            do { try await work() } catch { self.error = Self.message(for: error) }
        }
    }

    private static func message(for error: any Error) -> String {
        switch error {
        case ProviderError.unauthorized: "GitLab didn't accept that token. Check it has the read_api scope."
        case is URLError: "Couldn't reach GitLab. Check the server address and your connection."
        default: error.localizedDescription
        }
    }
}

private struct GitHubSetup: View {
    let model: AppModel
    @State private var useToken = !GitHubSignIn.isConfigured
    @State private var host = "https://github.com"
    @State private var token = ""
    @State private var code: GitHubSignIn.Code?
    @State private var signIn: Task<Void, Never>?
    @State private var error: String?
    @State private var working = false

    var body: some View {
        ProviderSetup(name: "GitHub", summary: "github.com or Enterprise Server", error: error) {
            if GitHubSignIn.isConfigured {
                if let code {
                    approval(code)
                } else {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sign in to github.com")
                            Text("You'll approve DevRings on GitHub with a one-time code.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if working && !useToken { ProgressView().controlSize(.small) }
                        Button("Sign In with GitHub…", action: startSignIn)
                            .buttonStyle(.borderedProminent)
                            .disabled(working)
                    }
                }
            }
            DisclosureGroup(GitHubSignIn.isConfigured ? "Use a token instead" : "Access token", isExpanded: $useToken) {
                VStack(alignment: .leading, spacing: 6) {
                    step(1, "Open GitHub's new token page, already filled in.") {
                        if let url = tokenPage { Link("Create Token", destination: url).font(.callout) }
                    }
                    step(2, "For work repositories, set **Resource owner** to your organisation.")
                    step(3, "Choose **Generate token**, then paste it below.")
                    Text("For GitHub Enterprise Server, or if you'd rather give read-only access. Some organisations approve new tokens before they work.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 26)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                TextField("Server", text: $host)
                LabeledContent("Token") {
                    SecureField("Token", text: $token, prompt: Text("github_pat_…"))
                        .labelsHidden()
                }
                HStack {
                    Spacer()
                    if working && useToken { ProgressView().controlSize(.small) }
                    Button("Connect", action: connectWithToken)
                        .disabled(token.isEmpty || working)
                }
            }
            DataUse(.gitHub)
        }
        .onDisappear { signIn?.cancel() }
    }

    private func approval(_ code: GitHubSignIn.Code) -> some View {
        VStack(spacing: 10) {
            Text("Enter this code on GitHub").foregroundStyle(.secondary)
            Text(code.userCode)
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                .textSelection(.enabled)
                .accessibilityLabel("Code \(code.userCode.map(String.init).joined(separator: " "))")
            HStack {
                Button("Cancel") {
                    signIn?.cancel()
                    self.code = nil
                    working = false
                }
                Button("Copy Code and Open GitHub") { open(code) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Waiting for you to approve on GitHub…").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var tokenPage: URL? {
        httpsURL(host)?.appending(path: "settings/personal-access-tokens/new").appending(queryItems: [
            .init(name: "name", value: "DevRings"),
            .init(name: "description", value: "Read-only: lets DevRings count the pull requests you merge and review."),
            .init(name: "expires_in", value: "366"),
            .init(name: "pull_requests", value: "read"),
        ])
    }

    private func open(_ code: GitHubSignIn.Code) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code.userCode, forType: .string)
        NSWorkspace.shared.open(code.verificationURI)
    }

    private func startSignIn() {
        working = true
        error = nil
        signIn = Task {
            defer {
                working = false
                code = nil
            }
            do {
                let code = try await GitHubSignIn.start()
                self.code = code
                open(code)
                let credentials = try await GitHubSignIn.waitForApproval(code)
                try await model.connectGitHub(credentials)
            } catch is CancellationError {
                return
            } catch {
                self.error = Self.message(for: error)
            }
        }
    }

    private func connectWithToken() {
        guard let server = httpsURL(host) else {
            error = "Enter the server's https:// address."
            return
        }
        working = true
        error = nil
        Task {
            defer { working = false }
            do {
                try await model.connectGitHub(GitHubCredentials(host: server, token: token.trimmingCharacters(in: .whitespacesAndNewlines)))
                token = ""
            } catch ProviderError.unauthorized {
                error = "GitHub didn't accept that token. Check it hasn't expired and has read access to pull requests."
            } catch {
                self.error = Self.message(for: error)
            }
        }
    }

    private static func message(for error: any Error) -> String {
        switch error {
        case is URLError: "Couldn't reach GitHub. Check the address and your connection."
        default: error.localizedDescription
        }
    }
}

private let atlassianTokenPage = URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!

private struct JiraSetup: View {
    let model: AppModel
    @State private var site = ""
    @State private var siteStatus: SiteStatus = .unknown
    @State private var email = ""
    @State private var token = ""
    @State private var error: String?
    @State private var working = false

    private enum SiteStatus { case unknown, checking, found, missing }

    var body: some View {
        ProviderSetup(name: "Jira Cloud", summary: "For a ticket ring", error: error) {
                steps
                siteField
                TextField("Email", text: $email, prompt: Text("The email you sign in to Atlassian with"))
                    .textContentType(.username)
                LabeledContent("API token") {
                    SecureField("API token", text: $token, prompt: Text("Paste your token"))
                        .labelsHidden()
                }
                HStack {
                    Spacer()
                    if working { ProgressView().controlSize(.small) }
                    Button("Connect", action: connect)
                        .disabled(siteStatus == .missing || site.isEmpty || email.isEmpty || token.isEmpty || working)
                        .keyboardShortcut(.defaultAction)
                }
                DataUse(.jira)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 6) {
            step(1, "Open your Atlassian API tokens page.") {
                Link("Open API Tokens", destination: atlassianTokenPage).font(.callout)
            }
            step(2, "Choose **Create API token**, name it “DevRings” and pick when it expires.")
            step(3, "Copy the token, then paste it below with your site and email.")
            Text("A token with scopes works too; give it read:jira-work and read:jira-user.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 26)
        }
        .padding(.vertical, 4)
    }


    private var siteField: some View {
        LabeledContent("Site") {
            HStack(spacing: 6) {
                TextField("Site", text: $site, prompt: Text("your-team.atlassian.net"))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                Group {
                    switch siteStatus {
                    case .unknown: EmptyView()
                    case .checking: ProgressView().controlSize(.small)
                    case .found: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            .help("Found \(JiraCredentials.site(from: site)?.host() ?? "the site")")
                    case .missing: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                            .help("No Jira site at that address")
                    }
                }
                .frame(width: 16)
            }
        }
        .task(id: site) { await checkSite() }
    }

    private func checkSite() async {
        guard let url = JiraCredentials.site(from: site) else {
            siteStatus = site.isEmpty ? .unknown : .missing
            return
        }
        siteStatus = .checking
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }
        let exists = await Jira.siteExists(url)
        guard !Task.isCancelled else { return }
        siteStatus = exists ? .found : .missing
    }

    private func connect() {
        guard let siteURL = JiraCredentials.site(from: site) else {
            error = "Enter your Atlassian site, like your-team.atlassian.net."
            return
        }
        run {
            try await model.connectJira(site: siteURL, email: email.trimmingCharacters(in: .whitespaces),
                                        token: token.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        working = true
        error = nil
        Task {
            defer { working = false }
            do {
                try await work()
                token = ""
            } catch ProviderError.unauthorized {
                error = "Jira didn't accept that token. Check it's for the same Atlassian account as the email, and that it hasn't expired."
            } catch is URLError {
                error = "Couldn't reach \(JiraCredentials.site(from: site)?.host() ?? model.jiraSite?.host() ?? "Jira"). Check your connection."
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct JiraConnected: View {
    let model: AppModel
    @State private var token = ""
    @State private var replacing = false
    @State private var error: String?
    @State private var working = false

    var body: some View {
        AccountRow(provider: "Jira", account: model.jiraAccount,
                   detail: [model.jiraSite?.host(), model.jiraConnection?.usesScopedToken == true ? "API token with scopes" : "API token"]
                       .compactMap { $0 }.joined(separator: " · "),
                   dataUse: .jira) {
            model.disconnectJira()
        }
        if replacing {
            LabeledContent("New token") {
                SecureField("New token", text: $token, prompt: Text("Paste the new token")).labelsHidden()
            }
            HStack {
                Link("Open API Tokens", destination: atlassianTokenPage)
                Spacer()
                if working { ProgressView().controlSize(.small) }
                Button("Cancel") {
                    replacing = false
                    token = ""
                    error = nil
                }
                Button("Save", action: replaceToken)
                    .disabled(token.isEmpty || working)
                    .keyboardShortcut(.defaultAction)
            }
        } else {
            HStack {
                Text("Tokens expire. When yours does, swap in a new one here.").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Replace Token…") { replacing = true }
            }
        }
        if let error { Text(error).font(.callout).foregroundStyle(.red) }
    }

    private func replaceToken() {
        working = true
        error = nil
        Task {
            defer { working = false }
            do {
                try await model.replaceJiraToken(token.trimmingCharacters(in: .whitespacesAndNewlines))
                token = ""
                replacing = false
            } catch ProviderError.unauthorized {
                error = "Jira didn't accept that token. Check it's for the same Atlassian account and hasn't expired."
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// A provider you haven't connected yet: one line until opened.
private struct ProviderSetup<Content: View>: View {
    let name: String
    let summary: String
    let error: String?
    @ViewBuilder let content: Content
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            content
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
        } label: {
            HStack {
                Text(name)
                Spacer()
                Text(summary).foregroundStyle(.secondary)
            }
        }
    }
}

/// What an account lets DevRings see, kept short and specific.
private struct DataUseInfo {
    let reads: [String]
    let stored: [String]
    let never: [String]

    static let gitLab = DataUseInfo(reads: [
        "Your name, username and avatar, to show who's connected.",
        "Merge requests you created and when they merged.",
        "Your activity feed, to find teammates' merge requests you commented on or approved. Comment text isn't kept.",
    ], stored: [
        "The token, in your Mac's Keychain.",
        "Merge request titles, projects and links in your history on this Mac, for up to a year.",
    ], never: [
        "Writes to GitLab: no comments, approvals or changes. The read_api scope can't.",
        "Reads code or diffs.",
        "Sends anything anywhere except your GitLab server. No analytics.",
    ])

    static let gitHub = DataUseInfo(reads: [
        "Your name, username and avatar, to show who's connected.",
        "Pull requests you opened and when they merged.",
        "Reviews and comments you left on teammates' pull requests, and when. Comment text isn't kept.",
    ], stored: [
        "The token, in your Mac's Keychain.",
        "Pull request titles, repositories and links in your history on this Mac, for up to a year.",
        "Disconnecting deletes the token from this Mac. To end a sign-in completely, also revoke DevRings in GitHub's Settings › Applications.",
    ], never: [
        "Writes to GitHub. Signing in needs GitHub's repo scope to read private repositories, which would allow writes, but DevRings only ever reads. A token can be strictly read-only.",
        "Reads code or diffs.",
        "Sends anything anywhere except GitHub. No analytics.",
    ])

    static let jira = DataUseInfo(reads: [
        "Your name and avatar, to show who's connected.",
        "Tickets whose status you changed each day: key, summary, status and project.",
        "Your site's labels, projects and open epics, to build the ticket ring filter.",
    ], stored: [
        "The token, in your Mac's Keychain.",
        "Ticket keys, summaries and statuses in your history on this Mac, for up to a year.",
    ], never: [
        "Creates, edits or moves anything in Jira.",
        "Reads descriptions, comments or attachments.",
        "Sends anything anywhere except your Jira site. No analytics.",
    ])
}

private struct DataUseList: View {
    let info: DataUseInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            group("Reads", symbol: "eye", tint: .blue, info.reads)
            group("Keeps on this Mac", symbol: "lock", tint: .secondary, info.stored)
            group("Never", symbol: "nosign", tint: .orange, info.never)
        }
    }

    private func group(_ title: String, symbol: String, tint: Color, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.callout.weight(.semibold)).foregroundStyle(tint)
            ForEach(lines, id: \.self) { line in
                Text("•  " + line).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A signed-in account: avatar, name and handle, with Disconnect.
private struct DataUse: View {
    let info: DataUseInfo
    init(_ info: DataUseInfo) { self.info = info }

    var body: some View {
        DisclosureGroup("What DevRings can see") {
            DataUseList(info: info).padding(.vertical, 6)
        }
    }
}

private struct AccountRow: View {
    let provider: String
    let account: AccountInfo?
    let detail: String
    let dataUse: DataUseInfo
    let disconnect: () -> Void
    @State private var showsDataUse = false

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: account?.avatar) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Text(initials).font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.secondary)
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(account?.name ?? "Checking…").font(.headline)
                Text([provider, account?.handle, detail].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showsDataUse.toggle()
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .help("What DevRings can see")
            .popover(isPresented: $showsDataUse, arrowEdge: .bottom) {
                DataUseList(info: dataUse).padding().frame(width: 360)
            }
            Button("Disconnect", action: disconnect)
        }
        .padding(.vertical, 2)
    }

    private var initials: String {
        String((account?.name ?? "").split(separator: " ").prefix(2).compactMap(\.first))
    }
}

@MainActor
private func step(_ number: Int, _ text: LocalizedStringKey, @ViewBuilder trailing: () -> some View = { EmptyView() }) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("\(number)")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Circle().fill(Color.accentColor))
        Text(text)
        Spacer(minLength: 8)
        trailing()
    }
}

/// An https URL from a typed server address, adding the scheme if it's missing.
private func httpsURL(_ text: String) -> URL? {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard let url = URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)"),
          url.scheme == "https", url.host() != nil else { return nil }
    return url
}

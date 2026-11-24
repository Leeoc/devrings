import DevRingsCore
import SwiftUI

struct AccountsView: View {
    let model: AppModel

    var body: some View {
        Form {
            GitLabSection(model: model)
            JiraSection(model: model)
        }
        .formStyle(.grouped)
    }
}

private struct GitLabSection: View {
    let model: AppModel
    @State private var useToken = !GitLabOAuth.isConfigured
    @State private var host = "https://gitlab.com"
    @State private var token = ""
    @State private var error: String?
    @State private var working = false

    var body: some View {
        Section {
            if model.codeHost != nil {
                AccountRow(account: model.gitLabAccount,
                           detail: model.gitLabUsesOAuth ? "Signed in with GitLab" : "Personal access token") {
                    model.disconnectGitLab()
                }
            } else {
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
                }
            }
            DataUse(reads: [
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
        } header: {
            Text("GitLab")
        } footer: {
            if let error {
                Text(error).foregroundStyle(.red)
            } else if model.codeHost == nil, useToken {
                Text("For self-hosted GitLab, or if you'd rather not sign in. Needs the read_api scope.")
            }
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

private struct JiraSection: View {
    let model: AppModel
    @State private var site = ""
    @State private var siteStatus: SiteStatus = .unknown
    @State private var email = ""
    @State private var token = ""
    @State private var replacing = false
    @State private var error: String?
    @State private var working = false

    private enum SiteStatus { case unknown, checking, found, missing }
    private static let tokenPage = URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!

    var body: some View {
        Section {
            if model.tracker != nil {
                connected
            } else {
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
            }
            DataUse(reads: [
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
        } header: {
            Text("Jira Cloud")
        } footer: {
            if let error {
                Text(error).foregroundStyle(.red)
            } else if model.tracker == nil {
                Text("Only needed for a ticket ring. Atlassian doesn't offer app sign-in for Jira yet, so DevRings uses an API token.")
            }
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 6) {
            step(1, "Open your Atlassian API tokens page.") {
                Link("Open API Tokens", destination: Self.tokenPage).font(.callout)
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

    @ViewBuilder private var connected: some View {
        AccountRow(account: model.jiraAccount, detail: model.jiraSite?.host() ?? "Jira Cloud") {
            model.disconnectJira()
        }
        LabeledContent("Token", value: model.jiraConnection?.usesScopedToken == true ? "API token with scopes" : "API token")
        if replacing {
            LabeledContent("New token") {
                SecureField("New token", text: $token, prompt: Text("Paste the new token")).labelsHidden()
            }
            HStack {
                Link("Open API Tokens", destination: Self.tokenPage)
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

    private func replaceToken() {
        run {
            try await model.replaceJiraToken(token.trimmingCharacters(in: .whitespacesAndNewlines))
            replacing = false
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

/// What an account lets DevRings see, kept short and specific.
private struct DataUse: View {
    let reads: [String]
    let stored: [String]
    let never: [String]
    @State private var expanded = false

    var body: some View {
        DisclosureGroup("What DevRings can see", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                group("Reads", symbol: "eye", tint: .blue, reads)
                group("Keeps on this Mac", symbol: "lock", tint: .secondary, stored)
                group("Never", symbol: "nosign", tint: .orange, never)
            }
            .padding(.vertical, 6)
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
private struct AccountRow: View {
    let account: AccountInfo?
    let detail: String
    let disconnect: () -> Void

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
                Text([account?.handle, detail].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Disconnect", action: disconnect)
        }
        .padding(.vertical, 2)
    }

    private var initials: String {
        String((account?.name ?? "").split(separator: " ").prefix(2).compactMap(\.first))
    }
}

/// An https URL from a typed server address, adding the scheme if it's missing.
private func httpsURL(_ text: String) -> URL? {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard let url = URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)"),
          url.scheme == "https", url.host() != nil else { return nil }
    return url
}

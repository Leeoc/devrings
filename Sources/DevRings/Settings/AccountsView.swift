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
    @State private var email = ""
    @State private var token = ""
    @State private var error: String?
    @State private var working = false

    var body: some View {
        Section {
            if model.tracker != nil {
                AccountRow(account: model.jiraAccount, detail: model.jiraSite?.host() ?? "Jira Cloud") {
                    model.disconnectJira()
                }
            } else {
                TextField("Site", text: $site, prompt: Text("your-team.atlassian.net"))
                TextField("Email", text: $email, prompt: Text("you@example.com"))
                    .textContentType(.username)
                LabeledContent("API token") {
                    HStack {
                        SecureField("API token", text: $token, prompt: Text("Paste your token"))
                            .labelsHidden()
                        Link("Create…", destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
                    }
                }
                HStack {
                    Spacer()
                    if working { ProgressView().controlSize(.small) }
                    Button("Connect", action: connect)
                        .disabled(site.isEmpty || email.isEmpty || token.isEmpty || working)
                        .keyboardShortcut(.defaultAction)
                }
            }
        } header: {
            Text("Jira Cloud")
        } footer: {
            if let error {
                Text(error).foregroundStyle(.red)
            } else if model.tracker == nil {
                Text("Only needed for a ticket ring. Atlassian doesn't offer app sign-in for Jira yet, so DevRings uses an API token, kept in your Keychain. Classic tokens work as they are; a scoped token needs read:jira-work and read:jira-user.")
            }
        }
    }

    private func connect() {
        guard let siteURL = JiraCredentials.site(from: site) else {
            error = "Enter your Atlassian site, like your-team.atlassian.net."
            return
        }
        working = true
        error = nil
        Task {
            defer { working = false }
            do {
                try await model.connectJira(site: siteURL, email: email.trimmingCharacters(in: .whitespaces),
                                            token: token.trimmingCharacters(in: .whitespacesAndNewlines))
                token = ""
            } catch ProviderError.unauthorized {
                error = "Jira didn't accept that email and token. Check the email matches your Atlassian account."
            } catch is URLError {
                error = "Couldn't reach \(siteURL.host() ?? "Jira"). Check your connection."
            } catch {
                self.error = error.localizedDescription
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

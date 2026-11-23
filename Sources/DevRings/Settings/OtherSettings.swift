import DevRingsCore
import ServiceManagement
import SwiftUI

struct AccountsView: View {
    let model: AppModel
    @State private var gitLabHost = "https://gitlab.com"
    @State private var gitLabToken = ""
    @State private var gitLabError: String?
    @State private var jiraSite = ""
    @State private var jiraEmail = ""
    @State private var jiraToken = ""
    @State private var jiraError: String?
    @State private var connecting = false

    var body: some View {
        Form {
            Section {
                if model.codeHost != nil {
                    LabeledContent("Signed in as", value: model.gitLabUser.map { "@\($0)" } ?? "Checking…")
                    Button("Disconnect", role: .destructive) { model.disconnectGitLab() }
                } else {
                    TextField("Server", text: $gitLabHost)
                    SecureField("Access token", text: $gitLabToken)
                    HStack {
                        if let url = httpsURL(gitLabHost)?.appending(path: "-/user_settings/personal_access_tokens")
                            .appending(queryItems: [.init(name: "name", value: "DevRings"), .init(name: "scopes", value: "read_api")]) {
                            Link("Create a token…", destination: url)
                        }
                        Spacer()
                        Button("Connect") { connectGitLab() }
                            .disabled(gitLabToken.isEmpty || connecting)
                    }
                }
            } header: {
                Text("GitLab")
            } footer: {
                if let gitLabError {
                    Text(gitLabError).foregroundStyle(.red)
                } else if model.codeHost == nil {
                    Text("Use a personal access token with the read_api scope. It's kept in your Keychain.")
                }
            }

            Section {
                if model.tracker != nil {
                    LabeledContent("Signed in as", value: model.jiraUser ?? "Checking…")
                    Button("Disconnect", role: .destructive) { model.disconnectJira() }
                } else {
                    TextField("Site", text: $jiraSite, prompt: Text("your-team.atlassian.net"))
                    TextField("Email", text: $jiraEmail)
                    SecureField("API token", text: $jiraToken)
                    HStack {
                        Link("Create an API token…", destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
                        Spacer()
                        Button("Connect") { connectJira() }
                            .disabled(jiraSite.isEmpty || jiraEmail.isEmpty || jiraToken.isEmpty || connecting)
                    }
                }
            } header: {
                Text("Jira Cloud")
            } footer: {
                if let jiraError {
                    Text(jiraError).foregroundStyle(.red)
                } else if model.tracker == nil {
                    Text("Only needed for a ticket ring. The token is kept in your Keychain.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func httpsURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)"),
              url.scheme == "https", url.host() != nil else { return nil }
        return url
    }

    private func connectGitLab() {
        guard let host = httpsURL(gitLabHost) else {
            gitLabError = "Enter an https:// server address."
            return
        }
        connecting = true
        Task {
            defer { connecting = false }
            do {
                try await model.connectGitLab(GitLabCredentials(host: host, token: gitLabToken.trimmingCharacters(in: .whitespaces)))
                gitLabToken = ""
                gitLabError = nil
            } catch {
                gitLabError = error.localizedDescription
            }
        }
    }

    private func connectJira() {
        guard let site = httpsURL(jiraSite) else {
            jiraError = "Enter your Atlassian site, like your-team.atlassian.net."
            return
        }
        connecting = true
        Task {
            defer { connecting = false }
            do {
                try await model.connectJira(JiraCredentials(site: site, email: jiraEmail.trimmingCharacters(in: .whitespaces),
                                                            token: jiraToken.trimmingCharacters(in: .whitespaces)))
                jiraToken = ""
                jiraError = nil
            } catch {
                jiraError = error.localizedDescription
            }
        }
    }
}

struct TimeOffView: View {
    @Bindable var model: AppModel
    @State private var start = Date.now
    @State private var end = Date.now

    var body: some View {
        Form {
            Section {
                HStack {
                    ForEach(weekdays, id: \.self) { weekday in
                        Toggle(Calendar.current.shortWeekdaySymbols[weekday - 1], isOn: Binding(
                            get: { model.settings.workingDays.contains(weekday) },
                            set: { on in
                                if on { model.settings.workingDays.insert(weekday) } else { model.settings.workingDays.remove(weekday) }
                            }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
            } header: {
                Text("Working days")
            } footer: {
                Text("Rings only run on working days. Other days never break a streak.")
            }

            Section {
                Toggle("Pause Today", isOn: Binding(get: { model.today.pause != nil }, set: { _ in model.togglePauseToday() }))
            } footer: {
                Text("Your rings grey out and your streak holds.")
            }

            Section("Time off") {
                ForEach(model.settings.pauseRanges.sorted { $0.start < $1.start }) { range in
                    LabeledContent(text(for: range)) {
                        Button(role: .destructive) {
                            model.settings.pauseRanges.removeAll { $0.id == range.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove")
                    }
                }
                DatePicker("From", selection: $start, displayedComponents: .date)
                DatePicker("To", selection: $end, in: start..., displayedComponents: .date)
                Button("Add Time Off") {
                    model.settings.pauseRanges.append(PauseRange(start: LocalDay.string(start), end: LocalDay.string(max(start, end))))
                }
            }

            Section {
                Toggle("Count days with no activity as time off", isOn: $model.settings.autoPauseIdleDays)
            } footer: {
                Text("A day off you forgot to pause won't break your streak. Turn this off for strict streaks.")
            }
        }
        .formStyle(.grouped)
    }

    private var weekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { ($0 + first - 1) % 7 + 1 }
    }

    private func text(for range: PauseRange) -> String {
        let start = LocalDay.start(range.start) ?? .now
        let end = LocalDay.start(range.end) ?? .now
        return range.start == range.end
            ? start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
            : (start..<end).formatted(.interval.day().month(.abbreviated).year())
    }
}

struct GeneralView: View {
    let model: AppModel
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                    }
            } footer: {
                if let loginError { Text(loginError).foregroundStyle(.red) }
            }
            Section {
                LabeledContent("History", value: model.days.count == 1 ? "1 day" : "\(model.days.count) days")
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Storage.directory]) }
            } footer: {
                Text("Everything stays on this Mac. DevRings keeps a year of history.")
            }
        }
        .formStyle(.grouped)
    }
}

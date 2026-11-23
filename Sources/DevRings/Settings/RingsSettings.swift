import Charts
import DevRingsCore
import SwiftUI

struct RingsSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Goals") {
                GoalRow(title: "Ship", caption: "MRs merged", goal: $model.settings.setup.shipGoal)
                GoalRow(title: "Review", caption: "teammates' MRs reviewed", goal: $model.settings.setup.reviewGoal)
            }
            Section {
                Toggle("Ticket ring", isOn: Binding(
                    get: { model.settings.setup.ticket != nil },
                    set: { model.settings.setup.ticket = $0 ? TicketRing(name: "Tech debt", goal: 2, filter: TicketFilter()) : nil }
                ))
            } footer: {
                Text("A third ring for tickets you move in Jira, such as tech debt or bugs.")
            }
            if let ring = Binding($model.settings.setup.ticket) {
                TicketRingEditor(model: model, ring: ring)
            }
        }
        .formStyle(.grouped)
    }
}

private struct GoalRow: View {
    let title: String
    let caption: String
    @Binding var goal: Int

    var body: some View {
        LabeledContent(title) {
            HStack {
                Text("\(goal) \(caption)").monospacedDigit()
                Stepper(title, value: $goal, in: 1...20).labelsHidden()
            }
        }
    }
}

private struct TicketRingEditor: View {
    let model: AppModel
    @Binding var ring: TicketRing

    @State private var labels: [String] = []
    @State private var projects: [TrackerOption] = []
    @State private var epics: [TrackerOption] = []
    @State private var query = ""
    @State private var loadError: String?
    @State private var preview: [PreviewDay] = []
    @State private var previewError: String?
    @State private var showAdvanced = false

    private struct PreviewDay: Identifiable {
        let day: String
        let count: Int
        var id: String { day }
    }

    var body: some View {
        Section("Ticket ring") {
            TextField("Name", text: $ring.name)
            GoalRow(title: "Goal", caption: "tickets moved", goal: $ring.goal)
        }
        .task { await loadOptions() }
        .task(id: ring.filter.project) { epics = (try? await model.trackerEpics(in: ring.filter.project)) ?? [] }

        if model.tracker == nil {
            Section {
                Text("Connect Jira in Accounts to pick labels, projects and epics, and to see a preview.")
                    .foregroundStyle(.secondary)
                Button("Open Accounts") { model.pane = .accounts }
            }
        } else {
            filter
            previewSection
        }
    }

    private var filter: some View {
        Section {
            LabeledContent("Labels") {
                if ring.filter.labels.isEmpty {
                    Text("Any label").foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(ring.filter.labels, id: \.self, content: token) }
                    }
                    .frame(maxWidth: 320, alignment: .trailing)
                }
            }
            TextField("Add a label", text: $query, prompt: Text("Search \(labels.count) labels"))
            ForEach(matches, id: \.self) { label in
                Button {
                    ring.filter.labels.append(label)
                    query = ""
                } label: {
                    Label(label, systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
            }
            if ring.filter.labels.count > 1 {
                Picker("Match", selection: $ring.filter.matchAllLabels) {
                    Text("Any of these").tag(false)
                    Text("All of these").tag(true)
                }
                .pickerStyle(.segmented)
            }
            Picker("Project", selection: $ring.filter.project) {
                Text("Any project").tag(String?.none)
                ForEach(projects) { Text($0.name).tag(String?.some($0.key)) }
            }
            Picker("Epic", selection: $ring.filter.epic) {
                Text("Any epic").tag(String?.none)
                ForEach(epics) { Text("\($0.key)  \($0.name)").tag(String?.some($0.key)) }
            }
            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                TextField("JQL", text: Binding(
                    get: { ring.filter.rawJQL ?? "" },
                    set: { ring.filter.rawJQL = $0.isEmpty ? nil : $0 }
                ), prompt: Text("labels = tech-debt OR parent = ABC-1"), axis: .vertical)
                .font(.body.monospaced())
                .lineLimit(2...5)
                Text("When set, this replaces the labels, project and epic above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Filter")
        } footer: {
            if let loadError { Text(loadError).foregroundStyle(.red) }
        }
        .onAppear { showAdvanced = ring.filter.rawJQL != nil }
    }

    private var previewSection: some View {
        Section {
            if let previewError {
                Text(previewError).foregroundStyle(.red)
            } else if preview.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Chart {
                    ForEach(preview) { point in
                        BarMark(x: .value("Day", (LocalDay.start(point.day) ?? .now).formatted(.dateTime.weekday(.abbreviated).day())),
                                y: .value("Tickets", point.count))
                            .foregroundStyle(RingKind.ticket.color)
                    }
                    RuleMark(y: .value("Goal", ring.goal))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.secondary)
                        .annotation(position: .top, alignment: .trailing) { Text("Goal").font(.caption2).foregroundStyle(.secondary) }
                }
                .frame(height: 150)
                Text(previewSummary).font(.callout).foregroundStyle(.secondary)
            }
        } header: {
            Text("Your last 10 working days")
        }
        .task(id: ring.filter) {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            do {
                preview = try await model.preview(ring.filter).map { PreviewDay(day: $0.day, count: $0.count) }
                previewError = nil
            } catch is CancellationError {
            } catch {
                previewError = "Jira couldn't run this filter. Check the JQL."
            }
        }
    }

    private var previewSummary: String {
        let counts = preview.map(\.count).sorted()
        let median = counts[counts.count / 2]
        let hits = counts.filter { $0 >= ring.goal }.count
        return "You'd have closed this ring on \(hits) of these \(counts.count) days. A typical day is \(median)."
    }

    private var matches: [String] {
        guard !query.isEmpty else { return [] }
        return Array(labels.filter { !ring.filter.labels.contains($0) && $0.localizedCaseInsensitiveContains(query) }.prefix(6))
    }

    private func token(_ label: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
            Button {
                ring.filter.labels.removeAll { $0 == label }
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Remove \(label)")
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary, in: Capsule())
    }

    private func loadOptions() async {
        guard model.tracker != nil else { return }
        do {
            async let labels = model.trackerLabels()
            async let projects = model.trackerProjects()
            (self.labels, self.projects) = try await (labels, projects)
        } catch {
            loadError = error.localizedDescription
        }
    }
}

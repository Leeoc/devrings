import DevRingsCore
import ServiceManagement
import SwiftUI

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
    @Bindable var model: AppModel
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                MenuBarStylePicker(day: model.today, selection: $model.settings.menuBarStyle,
                                   showsCount: model.settings.menuBarShowsCount)
                Toggle("Show rings closed beside the icon", isOn: $model.settings.menuBarShowsCount)
            } header: {
                Text("Menu bar")
            }
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

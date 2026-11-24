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
                WorkingDaysPicker(model: model)
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

    private func text(for range: PauseRange) -> String {
        let start = LocalDay.start(range.start) ?? .now
        let end = LocalDay.start(range.end) ?? .now
        return range.start == range.end
            ? start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
            : (start..<end).formatted(.interval.day().month(.abbreviated).year())
    }
}

struct WorkingDaysPicker: View {
    @Bindable var model: AppModel

    var body: some View {
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
    }

    private var weekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { ($0 + first - 1) % 7 + 1 }
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
            NotificationSettings(model: model)
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
                Button("Show Welcome…") { model.showOnboarding() }
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

private struct NotificationSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Section {
            switch model.notifier.authorization {
            case .notDetermined:
                HStack {
                    Text("Get a note when you close a ring, a nudge if you're behind, and a morning recap.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Turn On Notifications…") {
                        Task {
                            await model.notifier.requestPermission()
                            model.notifier.check(model.history)
                        }
                    }
                }
            case .denied:
                HStack {
                    Text("Notifications are off for DevRings in System Settings.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Open System Settings…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                    }
                }
            default:
                Toggle("When you close a ring", isOn: $model.settings.notifyClosed)
                Toggle(isOn: $model.settings.notifyBehind) {
                    Text("Nudge if you're behind")
                    Text("Only on working days, and only if a ring is still open.")
                }
                if model.settings.notifyBehind {
                    DatePicker("Nudge at", selection: time(\.behindHour, \.behindMinute), displayedComponents: .hourAndMinute)
                }
                Toggle(isOn: $model.settings.notifyRecap) {
                    Text("Morning recap")
                    Text("How your last working day went, with your streak and any awards.")
                }
                if model.settings.notifyRecap {
                    DatePicker("Recap at", selection: time(\.recapHour, \.recapMinute), displayedComponents: .hourAndMinute)
                }
            }
        } header: {
            Text("Notifications")
        }
        .task {
            // Permission can change in System Settings while the window is closed.
            await model.notifier.updateAuthorization()
        }
    }

    private func time(_ hour: WritableKeyPath<DevRingsCore.Settings, Int>, _ minute: WritableKeyPath<DevRingsCore.Settings, Int>) -> Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: model.settings[keyPath: hour], minute: model.settings[keyPath: minute], second: 0, of: .now) ?? .now
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            model.settings[keyPath: hour] = c.hour ?? 0
            model.settings[keyPath: minute] = c.minute ?? 0
        }
    }
}

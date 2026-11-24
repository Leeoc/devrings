import AppKit
import DevRingsCore
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let pointAtMenuBar: () -> Void
    private var window: NSWindow?

    init(model: AppModel, pointAtMenuBar: @escaping () -> Void) {
        self.model = model
        self.pointAtMenuBar = pointAtMenuBar
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: OnboardingView(model: model) { [weak self] in
                self?.window?.close()
                self?.pointAtMenuBar()
            })
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.title = "Welcome to DevRings"
            window.center()
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        model.settings.hasOnboarded = true
        let othersOpen = NSApp.windows.contains { $0 !== window && $0.isVisible && $0.styleMask.contains(.titled) }
        if !othersOpen { NSApp.setActivationPolicy(.accessory) }
        window = nil
    }
}

private enum Page: Int, CaseIterable {
    case welcome, code, tickets, week, done
}

struct OnboardingView: View {
    @Bindable var model: AppModel
    let finish: () -> Void
    @State private var page = CommandLine.arguments.firstIndex(of: "--onboarding")
        .flatMap { CommandLine.arguments.dropFirst($0 + 1).first }.flatMap(Int.init).flatMap(Page.init) ?? .welcome
    @State private var bounces = 0

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case .welcome: welcome
                case .code: code
                case .tickets: tickets
                case .week: week
                case .done: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            .id(page)

            Divider()
            HStack {
                HStack(spacing: 6) {
                    ForEach(Page.allCases, id: \.self) { p in
                        Circle().fill(p == page ? Color.primary : Color.secondary.opacity(0.35)).frame(width: 7, height: 7)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("Step \(page.rawValue + 1) of \(Page.allCases.count)")
                Spacer()
                if page != .welcome && page != .done {
                    Button("Back") { move(-1) }
                }
                continueButton
            }
            .padding(16)
        }
        .frame(width: 640, height: 640)
    }

    @ViewBuilder private var continueButton: some View {
        let button = Button(continueTitle) { page == .done ? finish() : move(1) }
            .buttonStyle(.borderedProminent)
        // While a Connect form is showing, Return belongs to its fields.
        if (page == .code && model.codeHosts.isEmpty) || (page == .tickets && model.tracker == nil) {
            button
        } else {
            button.keyboardShortcut(.defaultAction)
        }
    }

    private var continueTitle: String {
        switch page {
        case .welcome: "Get Started"
        case .code: model.codeHosts.isEmpty ? "Skip for Now" : "Continue"
        case .tickets: model.tracker == nil ? "Skip" : "Continue"
        case .week: "Continue"
        case .done: "Show Me"
        }
    }

    private func move(_ step: Int) {
        guard let next = Page(rawValue: page.rawValue + step) else { return }
        withAnimation(.snappy) { page = next }
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(spacing: 24) {
            Spacer()
            RingStack(rings: MenuBarIcon.example(like: model.settings.setup.emptyRecord(for: model.todayKey)).rings,
                      paused: false, lineWidth: 18, gap: 4)
                .frame(width: 160, height: 160)
            VStack(spacing: 6) {
                Text("Welcome to DevRings").font(.largeTitle.weight(.bold))
                Text("Close your rings for the work that matters.").font(.title3).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 14) {
                explainer(.ship, "Ship", "Your own merge and pull requests merged.")
                explainer(.review, "Review", "Teammates' work you reviewed. Each one counts once a day.")
                explainer(.ticket, "Tickets", "Optional: Jira tickets you move, like tech debt or bugs.")
            }
            .frame(maxWidth: 420)
            Spacer()
        }
        .padding(32)
    }

    private func explainer(_ kind: RingKind, _ name: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Circle().stroke(kind.color, lineWidth: 4).frame(width: 16, height: 16).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline)
                Text(text).foregroundStyle(.secondary)
            }
        }
    }

    private var code: some View {
        page("Connect your code", "Ship and Review fill in from GitLab or GitHub. Connect one or both.") {
            AccountsView(model: model, showsTickets: false)
        }
    }

    private var tickets: some View {
        page("Add a ticket ring", "Optional. A third ring for Jira tickets you move. You can do this later in Settings.") {
            VStack(spacing: 0) {
                AccountsView(model: model, showsCode: false)
                if model.tracker != nil {
                    Form {
                        Section {
                            Toggle("Ticket ring", isOn: Binding(
                                get: { model.settings.setup.ticket != nil },
                                set: { model.settings.setup.ticket = $0 ? TicketRing(name: "Tickets", goal: 2, filter: TicketFilter()) : nil }
                            ))
                        } footer: {
                            Text("Counts every ticket you move for now. Narrow it to labels, a project or an epic in Settings › Rings & Goals.")
                        }
                    }
                    .formStyle(.grouped)
                    .scrollDisabled(true)
                    .frame(height: 120)
                }
            }
        }
        .onChange(of: model.tracker == nil) { _, missing in
            if !missing, model.settings.setup.ticket == nil {
                model.settings.setup.ticket = TicketRing(name: "Tickets", goal: 2, filter: TicketFilter())
            }
        }
    }

    private var week: some View {
        page("Your week", "Rings only run on working days, and days off never break a streak.") {
            Form {
                Section("Working days") {
                    WorkingDaysPicker(model: model)
                }
                Section {
                    GoalRow(title: "Ship", caption: "merged", goal: $model.settings.setup.shipGoal)
                    GoalRow(title: "Review", caption: "reviewed", goal: $model.settings.setup.reviewGoal)
                    if let ticket = Binding($model.settings.setup.ticket) {
                        GoalRow(title: ticket.wrappedValue.name, caption: "moved", goal: ticket.goal)
                    }
                } header: {
                    Text("Daily goals")
                } footer: {
                    Text("Start small. You can change these any time.")
                }
            }
            .formStyle(.grouped)
        }
    }

    private var done: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.tint)
                .symbolEffect(.bounce, value: bounces)
                .task {
                    try? await Task.sleep(for: .milliseconds(400))
                    bounces += 1
                }
            Text("You're all set").font(.largeTitle.weight(.bold))
            Text("DevRings lives in your menu bar. Click the rings any time to see your day, or open History to look back.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            if model.codeHosts.isEmpty {
                Text("Connect GitLab or GitHub in Settings › Accounts when you're ready.")
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .padding(32)
    }

    private func page(_ title: String, _ subtitle: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(title).font(.title.weight(.bold))
                Text(subtitle).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.top, 40)
            .padding(.horizontal, 32)
            content()
        }
    }
}

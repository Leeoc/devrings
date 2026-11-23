import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show(_ pane: Pane?) {
        if let pane { model.pane = pane }
        if window == nil {
            let host = NSHostingController(rootView: MainView(model: model))
            host.sceneBridgingOptions = [.toolbars, .title]
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(NSSize(width: 1120, height: 800))
            window.center()
            window.setFrameAutosaveName("Main")
            window.title = "DevRings"
            self.window = window
        }
        // A Dock icon and Cmd-Tab entry only while the window is open.
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

struct MainView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { model.pane }, set: { if let pane = $0 { model.pane = pane } })) {
                Section {
                    Label("History", systemImage: "calendar").tag(Pane.history)
                    Label("Trends", systemImage: "chart.xyaxis.line").tag(Pane.trends)
                    Label("Awards", systemImage: "medal").tag(Pane.awards)
                }
                Section("Settings") {
                    Label("Rings & Goals", systemImage: "circle.circle").tag(Pane.rings)
                    Label("Accounts", systemImage: "person.crop.circle").tag(Pane.accounts)
                    Label("Time Off", systemImage: "beach.umbrella").tag(Pane.timeOff)
                    Label("General", systemImage: "gearshape").tag(Pane.general)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            detail
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await model.refresh() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .help("Refresh")
                        .keyboardShortcut("r")
                        .disabled(model.isRefreshing || model.isFixture)
                    }
                }
        }
        .navigationTitle(title)
        .frame(minWidth: 980, minHeight: 640)
    }

    @ViewBuilder private var detail: some View {
        switch model.pane {
        case .history: HistoryView(model: model)
        case .trends: TrendsView(history: model.history)
        case .awards: AwardsView(history: model.history)
        case .rings: RingsSettingsView(model: model)
        case .accounts: AccountsView(model: model)
        case .timeOff: TimeOffView(model: model)
        case .general: GeneralView(model: model)
        }
    }

    private var title: String {
        switch model.pane {
        case .history: "History"
        case .trends: "Trends"
        case .awards: "Awards"
        case .rings: "Rings & Goals"
        case .accounts: "Accounts"
        case .timeOff: "Time Off"
        case .general: "General"
        }
    }
}

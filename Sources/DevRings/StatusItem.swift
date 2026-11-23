import AppKit
import DevRingsCore
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let header = NSMenuItem()
    private let model: AppModel
    private let openWindow: (Pane) -> Void

    init(model: AppModel, openWindow: @escaping (Pane) -> Void) {
        self.model = model
        self.openWindow = openWindow
        super.init()
        if let button = item.button {
            let icon = PassthroughHostingView(rootView: MenuBarRings(model: model))
            icon.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(icon)
            NSLayoutConstraint.activate([
                icon.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                icon.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 18),
                icon.heightAnchor.constraint(equalToConstant: 18),
            ])
            button.setAccessibilityLabel("DevRings")
        }
        menu.delegate = self
        menu.addItem(header)
        item.menu = menu
        observeModel()
    }

    func open() {
        item.button?.performClick(nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        model.refreshIfStale()
        // A fresh view each time so the rings replay their opening animation.
        let view = NSHostingView(rootView: MenuHeader(model: model))
        view.frame = NSRect(x: 0, y: 0, width: 280, height: 168)
        view.autoresizingMask = .width
        header.view = view
        rebuildRows()
    }

    private func observeModel() {
        withObservationTracking {
            _ = (model.days, model.settings, model.errors, model.lastRefresh, model.isRefreshing)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.rebuildRows()
                self?.observeModel()
            }
        }
    }

    /// Everything below the rings header, which stays put so its animation isn't cut short.
    private func rebuildRows() {
        while menu.items.count > 1 { menu.removeItem(at: 1) }
        let day = model.today

        menu.addItem(.sectionHeader(title: LocalDay.start(day.date).map(Self.dateTitle) ?? day.date))
        let columns = RingRowColumns(day.rings)
        for ring in day.rings { menu.addItem(row(for: ring, columns: columns)) }

        menu.addItem(.separator())
        for error in model.errors {
            let item = NSMenuItem(title: error, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(action(day.pause == nil ? "Pause Today" : "Resume Today", #selector(togglePause)))
        menu.addItem(action("Open DevRings", #selector(openHistory), key: "o"))
        menu.addItem(action("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit DevRings", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        // macOS adds its own icon to standard titles like "Settings…"; setting then clearing an image opts out,
        // which keeps this menu consistently icon-free.
        item.image = NSImage()
        item.image = nil
        return item
    }

    private func row(for ring: RingResult, columns: RingRowColumns) -> NSMenuItem {
        let row = NSMenuItem()
        row.attributedTitle = columns.title(for: ring)
        // The state column, because macOS 27 hides menu item images for apps built on current SDKs.
        row.state = ring.isClosed ? .on : .off

        let submenu = NSMenu()
        if ring.items.isEmpty {
            let none = NSMenuItem(title: "Nothing yet today", action: nil, keyEquivalent: "")
            none.isEnabled = false
            submenu.addItem(none)
        }
        for entry in ring.items {
            let link = NSMenuItem(title: entry.title, action: #selector(openLink(_:)), keyEquivalent: "")
            link.target = self
            link.representedObject = entry.url
            link.attributedTitle = Self.linkTitle(entry)
            link.toolTip = entry.title
            submenu.addItem(link)
        }
        row.submenu = submenu
        return row
    }

    @objc private func togglePause() {
        model.togglePauseToday()
    }

    @objc private func openHistory() {
        openWindow(.history)
    }

    @objc private func openSettings() {
        openWindow(.rings)
    }

    @objc private func openLink(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.open(url) }
    }

    private static func dateTitle(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private static func linkTitle(_ entry: RingItem) -> NSAttributedString {
        let clean = entry.displayTitle(hiding: [])
        let title = clean.count > 60 ? clean.prefix(59) + "…" : clean
        let shortRef = entry.ref.split(separator: "/").last.map(String.init) ?? entry.ref
        let text = NSMutableAttributedString(string: title + "  ", attributes: [.font: NSFont.menuFont(ofSize: 0)])
        text.append(NSAttributedString(string: shortRef, attributes: [
            .font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return text
    }
}

/// Lines up name, count and caption across the ring rows with tab stops measured from the widest of each.
@MainActor
private struct RingRowColumns {
    private let paragraph = NSMutableParagraphStyle()
    private static let font = NSFont.menuFont(ofSize: 0)
    private static let countFont = NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .semibold)

    init(_ rings: [RingResult]) {
        func width(_ s: String, _ font: NSFont) -> CGFloat { (s as NSString).size(withAttributes: [.font: font]).width }
        let nameEnd = rings.map { width($0.name, Self.font) }.max() ?? 0
        let countEnd = nameEnd + 14 + (rings.map { width(Self.count($0), Self.countFont) }.max() ?? 0)
        paragraph.tabStops = [NSTextTab(textAlignment: .left, location: nameEnd + 14),
                              NSTextTab(textAlignment: .left, location: countEnd + 12)]
    }

    func title(for ring: RingResult) -> NSAttributedString {
        let text = NSMutableAttributedString(string: ring.name + "\t", attributes: [.font: Self.font, .paragraphStyle: paragraph])
        text.append(NSAttributedString(string: Self.count(ring) + "\t", attributes: [.font: Self.countFont, .paragraphStyle: paragraph]))
        text.append(NSAttributedString(string: ring.id.caption, attributes: [
            .font: Self.font, .paragraphStyle: paragraph, .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return text
    }

    private static func count(_ ring: RingResult) -> String { "\(ring.count)/\(ring.goal)" }
}

private extension RingID {
    var caption: String {
        switch self {
        case .ship: "MRs merged"
        case .review: "teammates' MRs reviewed"
        case .ticket: "tickets moved"
        }
    }
}

struct MenuHeader: View {
    let model: AppModel

    var body: some View {
        let day = model.today
        RingStack(rings: day.rings, paused: day.pause != nil, lineWidth: 15, gap: 2.5)
            .frame(width: 136, height: 136)
            .overlay {
                if day.pause != nil { Text("Paused").font(.headline).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Lets clicks fall through to the status bar button underneath.
private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

import AppKit
import DevRingsCore
import SwiftUI

@main
enum DevRingsMain {
    @MainActor static func main() {
        let arguments = CommandLine.arguments
        if let i = arguments.firstIndex(of: "--render-icon"), i + 1 < arguments.count {
            exit(AppIcon.render(into: URL(filePath: arguments[i + 1])) ? 0 : 1)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusItem: StatusItemController?
    private lazy var mainWindow = MainWindowController(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = mainMenu()
        let statusItem = StatusItemController(model: model) { [weak self] pane in self?.mainWindow.show(pane) }
        self.statusItem = statusItem
        model.start()
        if CommandLine.arguments.contains("--open-menu") {
            Task { statusItem.open() }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--open-window") {
            let pane = CommandLine.arguments.dropFirst(i + 1).first.flatMap(Pane.init(rawValue:)) ?? .history
            mainWindow.show(pane)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        mainWindow.show(nil)
        return false
    }

    @objc private func openSettings() {
        mainWindow.show(.rings)
    }

    /// Only shown while the window is open, but needed for ⌘C/⌘V in text fields and ⌘W.
    private func mainMenu() -> NSMenu {
        func item(_ title: String, _ action: Selector?, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            return item
        }
        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = menu
            return item
        }
        let settings = item("Settings…", #selector(openSettings), ",")
        settings.target = self
        let main = NSMenu()
        main.addItem(submenu("DevRings", [
            item("About DevRings", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""),
            .separator(), settings, .separator(),
            item("Hide DevRings", #selector(NSApplication.hide(_:)), "h"),
            item("Quit DevRings", #selector(NSApplication.terminate(_:)), "q"),
        ]))
        main.addItem(submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"), item("Redo", Selector(("redo:")), "z", [.command, .shift]), .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"), item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"), item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ]))
        main.addItem(submenu("Window", [
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
        ]))
        return main
    }
}

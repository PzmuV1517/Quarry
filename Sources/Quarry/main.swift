import AppKit
import QuarryKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let library = ToolLibrary()
    private var window: QuarryWindowController?
    private var statusBar: StatusBar?

    /// Set up before launch finishes: a `quarry://` link that launched Quarry arrives in
    /// `application(_:open:)` before `applicationDidFinishLaunching`.
    func applicationWillFinishLaunching(_ notification: Notification) {
        let window = QuarryWindowController(library: library)
        self.window = window
        let statusBar = StatusBar(library: library) { window.show($0) }
        self.statusBar = statusBar
        library.onChange = { statusBar.update() }
        library.host.onShowPage = { tool, page in window.show(tool: tool, page: page) }
        NSApp.mainMenu = Self.mainMenu(target: self)
        library.launch()

        // `--window[=<destination>]` opens the window on launch (handy for screenshots).
        if let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--window") }) {
            window.show(Destination(argument: String(argument.drop { $0 != "=" }.dropFirst())))
        }
    }

    /// `quarry://tool/<bundle id>[/<page>]`, sent by tools opened on their own while Quarry
    /// runs them.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "quarry" && url.host == "tool" {
            let parts = url.pathComponents.filter { $0 != "/" }
            guard let id = parts.first else { continue }
            window?.show(tool: id, page: parts.dropFirst().first)
        }
    }

    /// Opening Quarry again (e.g. from Finder or Spotlight) shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window?.show()
        return false
    }

    @objc private func showSettings() { window?.show() }
    @objc private func showAbout() { window?.show(.settings) }

    /// The menu bar shown while the window is in front, mostly so text fields get copy and paste
    /// and the window closes with ⌘W.
    private static func mainMenu(target: AppDelegate) -> NSMenu {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "About Quarry", action: #selector(showAbout), keyEquivalent: "").target = target
        app.addItem(.separator())
        app.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = target
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Quarry", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit Quarry", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")

        for (title, submenu) in [("Quarry", app), ("Edit", edit), ("Window", window)] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            main.addItem(item)
        }
        return main
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

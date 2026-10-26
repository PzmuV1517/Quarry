import AppKit
import QuarryKit

/// Quarry's one menu bar item. Each running tool adds its own section to the menu.
@MainActor
final class StatusBar: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let library: ToolLibrary
    private let open: (Destination?) -> Void

    init(library: ToolLibrary, open: @escaping (Destination?) -> Void) {
        self.library = library
        self.open = open
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        update()
    }

    func update() {
        guard let button = item.button else { return }
        if library.needsAccessibility && !library.accessibilityGranted {
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Quarry")
        } else {
            button.image = Self.gem
        }
        button.imagePosition = .imageLeading
        let titles = library.managed.compactMap(\.menuBarTitle)
        button.title = titles.isEmpty ? "" : " " + titles.joined(separator: " ")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if library.needsAccessibility && !library.accessibilityGranted {
            menu.addItem(disabled("Needs Accessibility access"))
            menu.addItem(action("Open Accessibility Settings…") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            })
            menu.addItem(.separator())
        }

        for tool in library.managed {
            menu.addItem(.sectionHeader(title: tool.name))
            if let error = tool.loadError {
                menu.addItem(disabled(error))
            } else if tool.isStarted, let instance = tool.instance {
                instance.populateMenu(menu)
            } else {
                menu.addItem(disabled("Waiting to start"))
            }
            menu.addItem(.separator())
        }
        if library.managed.isEmpty {
            menu.addItem(action("Get Tools…") { [weak self] in self?.open(.library) })
            menu.addItem(.separator())
        }

        if !library.updatesAvailable.isEmpty {
            menu.addItem(action("Updates Available…") { [weak self] in self?.open(.library) })
        }
        menu.addItem(action("Quarry Settings…", key: ",") { [weak self] in self?.open(nil) })
        menu.addItem(action("Quit Quarry", key: "q") { NSApp.terminate(nil) })
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, key: String = "", _ handler: @escaping @MainActor () -> Void) -> NSMenuItem {
        ClosureMenuItem(title: title, keyEquivalent: key, handler: handler)
    }

    /// A cut gem, drawn as a template so it follows the menu bar's appearance.
    static let gem: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let outline = NSBezierPath()
            outline.move(to: NSPoint(x: 5.5, y: 3))
            outline.line(to: NSPoint(x: 12.5, y: 3))
            outline.line(to: NSPoint(x: 16.5, y: 7.5))
            outline.line(to: NSPoint(x: 9, y: 16))
            outline.line(to: NSPoint(x: 1.5, y: 7.5))
            outline.close()
            outline.lineWidth = 1.4
            outline.lineJoinStyle = .round
            outline.stroke()

            let facets = NSBezierPath()
            facets.move(to: NSPoint(x: 1.5, y: 7.5))
            facets.line(to: NSPoint(x: 16.5, y: 7.5))
            facets.move(to: NSPoint(x: 5.5, y: 3))
            facets.line(to: NSPoint(x: 7, y: 7.5))
            facets.line(to: NSPoint(x: 9, y: 16))
            facets.line(to: NSPoint(x: 11, y: 7.5))
            facets.line(to: NSPoint(x: 12.5, y: 3))
            facets.lineWidth = 1
            facets.lineJoinStyle = .round
            facets.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Quarry"
        return image
    }()
}

@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, keyEquivalent: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}

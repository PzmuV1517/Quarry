import AppKit
import QuarryKit
import SwiftUI

/// A page in Quarry's window.
enum Destination: Hashable {
    /// One of a tool's own settings pages.
    case toolPage(String, String)
    /// Every tool, Quarry included: installing, updating, versions, removing.
    case library
    /// Quarry's own settings, with About Quarry at the bottom.
    case settings

    /// `tool:<id>[:<page>]`, `library` or `settings`, as used by `Quarry --window=<destination>`.
    init?(argument: String) {
        let parts = argument.split(separator: ":").map(String.init)
        switch parts.first {
        case "tool" where parts.count == 3: self = .toolPage(parts[1], parts[2])
        case "library": self = .library
        case "settings": self = .settings
        default: return nil
        }
    }
}

@MainActor
@Observable
final class Navigation {
    var destination: Destination = .library
}

/// Owns Quarry's window. While it's open Quarry shows in the Dock and ⌘-Tab like a regular
/// app; when it closes Quarry goes back to living only in the menu bar.
@MainActor
final class QuarryWindowController: NSObject, NSWindowDelegate {
    private let library: ToolLibrary
    private let navigation = Navigation()
    private var window: NSWindow?

    init(library: ToolLibrary) {
        self.library = library
    }

    /// Opens on `destination`, or on the first tool's first page.
    func show(_ destination: Destination? = nil) {
        navigation.destination = destination ?? defaultDestination
        let window = window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // Opened from a link or another app, macOS may not let Quarry activate; show it anyway.
        window.orderFrontRegardless()
    }

    /// For `quarry://tool/<id>[/<page>]`.
    func show(tool id: String, page: String?) {
        guard let tool = library.tool(id) else { return show(.library) }
        if let page, tool.pages.contains(where: { $0.id == page }) {
            show(.toolPage(id, page))
        } else if let first = tool.pages.first {
            show(.toolPage(id, first.id))
        } else {
            show(.library)
        }
    }

    private var defaultDestination: Destination {
        guard let tool = library.managed.first(where: { !$0.pages.isEmpty }) else { return .library }
        return .toolPage(tool.id, tool.pages[0].id)
    }

    private func makeWindow() -> NSWindow {
        let root = QuarryView(library: library, navigation: navigation)
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = "Quarry"
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)  // the Ferriteworks look is black-only
        window.backgroundColor = .black
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: 900, height: 620))
        window.minSize = NSSize(width: 760, height: 480)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    func windowWillClose(_ notification: Notification) {
        library.host.easterEgg.back()  // stops a tool's finale, which would keep playing
        NSApp.setActivationPolicy(.accessory)
    }
}

struct QuarryView: View {
    let library: ToolLibrary
    @Bindable var navigation: Navigation

    var body: some View {
        NavigationSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    // Each tool's own pages; everything about installing and updating is in Library.
                    ForEach(library.managed.filter { !$0.pages.isEmpty }) { tool in
                        SidebarHeading(tool.name).windowElement("heading.\(tool.id)", library.host.easterEgg)
                        ForEach(tool.pages) { page in
                            item(page.title, symbol: page.symbol, .toolPage(tool.id, page.id))
                        }
                    }
                    SidebarHeading("Quarry").windowElement("heading.quarry", library.host.easterEgg)
                    item("Library", symbol: "square.grid.2x2", .library, badge: !library.updatesAvailable.isEmpty || library.managed.contains { $0.loadError != nil })
                    item("Settings", symbol: "gearshape", .settings)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
                .onPreferenceChange(ElementFrames.self) { frames in
                    MainActor.assumeIsolated { library.host.easterEgg.frames = frames }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            detail
                .id(navigation.destination)
                .navigationTitle("")
        }
        .allowsHitTesting(!library.host.easterEgg.isPlaying)
        .overlay {
            if let finale = library.host.easterEgg.finale {
                EasterEggFinale(back: { library.host.easterEgg.back() }) { HostedController(controller: finale).ignoresSafeArea() }
                    .transition(.opacity)
            }
        }
        .coordinateSpace(name: Self.space)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { library.host.easterEgg.windowHeight = $0 }
        .environment(\.solidGlass, library.host.easterEgg.isPlaying)
        .ferriteStyle()
    }

    /// The whole window's content, where sidebar frames are measured.
    static let space = "quarry.window"

    private func item(_ title: String, symbol: String, _ destination: Destination, badge: Bool = false) -> some View {
        SidebarButton(title, isSelected: navigation.destination == destination, action: { navigation.destination = destination }) {
            Image(systemName: symbol)
                .overlay(alignment: .topTrailing) {
                    if badge { Circle().fill(Brand.primary).frame(width: 6, height: 6).offset(x: 3, y: -2) }
                }
        }
        .windowElement("\(destination)", library.host.easterEgg)
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.destination {
        case .toolPage(let id, let page):
            if let instance = library.tool(id)?.instance {
                ToolPage(tool: instance, page: page).ignoresSafeArea()
            } else {
                PageContainer { Text("This page isn't available.").foregroundStyle(Brand.secondary) }
            }
        case .library:
            PageContainer { LibraryPage(library: library, navigation: navigation) }
        case .settings:
            PageContainer { SettingsPage(library: library) }
        }
    }
}

/// Quarry's own window elements, by id, in the window: tools' easter eggs make them fall.
private struct ElementFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private extension View {
    func windowElement(_ id: String, _ easterEgg: WindowEasterEgg) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: ElementFrames.self, value: [id: geometry.frame(in: .named(QuarryView.space))])
        })
        .easterEggMove(easterEgg.moves[id])
    }
}

/// A view controller handed over by a tool, such as its easter egg's finale.
struct HostedController: NSViewControllerRepresentable {
    let controller: NSViewController

    func makeNSViewController(context: Context) -> NSViewController { controller }
    func updateNSViewController(_ controller: NSViewController, context: Context) {}
}

/// A tool's page, made by the tool and filling the whole detail area.
struct ToolPage: NSViewControllerRepresentable {
    let tool: QuarryTool
    let page: String

    func makeNSViewController(context: Context) -> NSViewController {
        tool.makePage(page)
    }

    func updateNSViewController(_ controller: NSViewController, context: Context) {}
}

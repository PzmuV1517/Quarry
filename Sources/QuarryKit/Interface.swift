import AppKit

/// The contract between Quarry and the tools it loads.
///
/// A tool ships its code as a dynamic library in its app's `Contents/Frameworks` and names it in
/// Info.plist under `QuarryLibrary`. Run on its own, the app loads that library itself. Installed
/// through Quarry, Quarry loads it into its own process instead, so every tool shares one menu
/// bar item and one settings window. The library exports two C functions:
///
///     @_cdecl("quarry_interface_version")
///     public func quarryInterfaceVersion() -> Int32 { QuarryInterface.version }
///
///     @_cdecl("quarry_tool_make")
///     public func quarryToolMake(_ host: UnsafeRawPointer) -> UnsafeMutableRawPointer? {
///         // Called on the main thread. The pointer leaves as an address, which is Sendable.
///         let address = MainActor.assumeIsolated {
///             UInt(bitPattern: QuarryInterface.export(MyTool(host: QuarryInterface.host(from: host))))
///         }
///         return UnsafeMutableRawPointer(bitPattern: address)
///     }
///
/// Only Objective-C protocols and AppKit objects cross between Quarry and a tool. QuarryKit is
/// compiled into both sides separately, so its Swift types are never shared, and it must not
/// declare classes: the Objective-C runtime would see each one twice.
public enum QuarryInterface {
    /// Bumped on breaking changes; Quarry won't load a tool built for another version.
    public static let version: Int32 = 1
    public static let versionSymbol = "quarry_interface_version"
    public static let makeSymbol = "quarry_tool_make"

    /// Info.plist key naming the library in `Contents/Frameworks`.
    public static let libraryKey = "QuarryLibrary"
    /// Info.plist key: `true` if the tool needs Accessibility access before it can start.
    public static let accessibilityKey = "QuarryNeedsAccessibility"

    public typealias VersionFunction = @convention(c) () -> Int32
    public typealias MakeFunction = @convention(c) (UnsafeRawPointer) -> UnsafeMutableRawPointer?

    /// In a tool's `quarry_tool_make`: the host Quarry passed in.
    public static func host(from pointer: UnsafeRawPointer) -> QuarryHost? {
        Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue() as? QuarryHost
    }

    /// In a tool's `quarry_tool_make`: hands the tool to Quarry, which takes ownership.
    public static func export(_ tool: QuarryTool) -> UnsafeMutableRawPointer {
        Unmanaged.passRetained(tool as AnyObject).toOpaque()
    }
}

/// What Quarry offers the tools it loads.
@MainActor
@objc(QuarryHost)
public protocol QuarryHost: NSObjectProtocol {
    /// Tells Quarry something it shows for the tool changed, such as its menu bar title.
    func toolDidChange(_ identifier: String)
    /// Opens Quarry's window on one of the tool's pages.
    func showPage(_ page: String, ofTool identifier: String)

    /// Plays a tool's easter egg across Quarry's whole window. Quarry's own elements and the
    /// tool's `pieces` (frames in the window's content view, origin at the top left) fall
    /// together. Quarry calls `move` with each piece's `[dx, dy, radians]` as they fall, and with
    /// an empty dictionary to put them back. Then it shows `finale` over the whole window with a
    /// Back button; the finale calls the block it's given to end early. QuarryKit's
    /// `easterEggStage(host:)` does all of this for a tool.
    @objc optional func playEasterEgg(
        pieces: [String: NSValue],
        move: @escaping ([String: [NSNumber]]) -> Void,
        finale: @escaping (@escaping () -> Void) -> NSViewController
    )
}

/// A tool running inside Quarry.
@MainActor
@objc(QuarryTool)
public protocol QuarryTool: NSObjectProtocol {
    /// Settings pages in sidebar order, each made with `QuarryPage.dictionary`.
    var pages: [[String: String]] { get }

    /// Called once Quarry has the permissions the tool asked for.
    func start()

    /// Adds the tool's items to Quarry's menu, under a header with the tool's name. Called each
    /// time the menu opens. Leave out About, Quit and Open at Login; Quarry has those.
    func populateMenu(_ menu: NSMenu)

    /// One of `pages`, filling the whole detail area of Quarry's window.
    func makePage(_ id: String) -> NSViewController

    /// Short text next to Quarry's menu bar icon, like the Desktop number Spinel shows.
    @objc optional var menuBarTitle: String? { get }
}

/// A settings page as listed in `QuarryTool.pages`.
public struct QuarryPage: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    /// SF Symbol name.
    public let symbol: String

    public init(id: String, title: String, symbol: String) {
        self.id = id
        self.title = title
        self.symbol = symbol
    }

    public init?(_ dictionary: [String: String]) {
        guard let id = dictionary["id"], let title = dictionary["title"] else { return nil }
        self.init(id: id, title: title, symbol: dictionary["symbol"] ?? "square")
    }

    public var dictionary: [String: String] { ["id": id, "title": title, "symbol": symbol] }
}

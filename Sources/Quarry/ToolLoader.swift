import AppKit
import QuarryKit
import SwiftUI

/// Loads a tool's library out of its app bundle into Quarry (see `QuarryInterface`).
///
/// A loaded library can't be unloaded, so replacing or removing a running tool means
/// relaunching Quarry.
@MainActor
enum ToolLoader {
    static func load(_ app: URL, host: QuarryHost) throws -> QuarryTool {
        guard let bundle = Bundle(url: app),
              let name = bundle.object(forInfoDictionaryKey: QuarryInterface.libraryKey) as? String,
              let frameworks = bundle.privateFrameworksURL
        else { throw ReleaseError("This version can't run in Quarry. Update it first.") }

        let path = frameworks.appendingPathComponent(name).path
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            throw ReleaseError("Couldn't load \(name): \(String(cString: dlerror()))")
        }
        guard let versionSymbol = dlsym(handle, QuarryInterface.versionSymbol),
              let makeSymbol = dlsym(handle, QuarryInterface.makeSymbol)
        else { throw ReleaseError("\(name) isn't a Quarry tool") }

        let version = unsafeBitCast(versionSymbol, to: QuarryInterface.VersionFunction.self)()
        guard version == QuarryInterface.version else {
            throw ReleaseError(version < QuarryInterface.version
                ? "This version is too old for Quarry. Update it."
                : "This version needs a newer Quarry. Update Quarry.")
        }
        let make = unsafeBitCast(makeSymbol, to: QuarryInterface.MakeFunction.self)
        guard let pointer = make(Unmanaged.passUnretained(host as AnyObject).toOpaque()),
              let tool = Unmanaged<AnyObject>.fromOpaque(pointer).takeRetainedValue() as? QuarryTool
        else { throw ReleaseError("\(name) didn't start") }
        return tool
    }
}

/// Quarry's side of `QuarryHost`, handed to every tool it loads.
@MainActor
final class HostBridge: NSObject, QuarryHost {
    var onChange: ((String) -> Void)?
    var onShowPage: ((String, String) -> Void)?
    let easterEgg = WindowEasterEgg()

    func toolDidChange(_ identifier: String) {
        onChange?(identifier)
    }

    func showPage(_ page: String, ofTool identifier: String) {
        onShowPage?(identifier, page)
    }

    func playEasterEgg(
        pieces: [String: NSValue],
        move: @escaping ([String: [NSNumber]]) -> Void,
        finale: @escaping (@escaping () -> Void) -> NSViewController
    ) {
        easterEgg.play(pieces: pieces.mapValues(\.rectValue), move: move, finale: finale)
    }
}

/// A tool's easter egg played across Quarry's window: the sidebar entries fall along with the
/// tool's pieces, then the tool's finale covers the window.
@MainActor
@Observable
final class WindowEasterEgg {
    /// Where Quarry's own elements are, kept up to date by the window, and how far they've fallen.
    @ObservationIgnored var frames: [String: CGRect] = [:]
    @ObservationIgnored var windowHeight: CGFloat = 0
    private(set) var moves: [String: FallMove] = [:]
    private(set) var isPlaying = false
    private(set) var finale: NSViewController?
    @ObservationIgnored private var moveTool: (([String: [NSNumber]]) -> Void)?

    func play(pieces: [String: CGRect], move: @escaping ([String: [NSNumber]]) -> Void, finale: @escaping (@escaping () -> Void) -> NSViewController) {
        guard !isPlaying else { return }
        isPlaying = true
        moveTool = move
        let tool = "tool."
        let all = frames.merging(pieces.map { (tool + $0.key, $0.value) }) { $1 }
        Task {
            var simulation = FallSimulation(frames: all, floor: windowHeight)
            while !simulation.isDone {
                simulation.step(FallSimulation.tick)
                moves = simulation.moves.filter { !$0.key.hasPrefix(tool) }
                move(Dictionary(uniqueKeysWithValues: simulation.moves.compactMap { id, fall in
                    id.hasPrefix(tool) ? (String(id.dropFirst(tool.count)), fall.numbers) : nil
                }))
                try? await Task.sleep(for: .seconds(FallSimulation.tick))
            }
            let controller = finale { [weak self] in self?.back() }
            withAnimation(.easeOut(duration: 0.4)) { self.finale = controller }
        }
    }

    func back() {
        guard finale != nil else { return }
        withAnimation(.easeOut(duration: 0.3)) { finale = nil }
        withAnimation(.spring(duration: 0.8, bounce: 0.25)) { moves = [:] }
        moveTool?([:])
        moveTool = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { [weak self] in self?.isPlaying = false }
    }
}

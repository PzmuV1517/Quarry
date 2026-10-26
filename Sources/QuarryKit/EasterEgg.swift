import AVFoundation
import AppKit
import OSLog
import SwiftUI

// Easter eggs for any tool: mark views `.fallable`, wrap the window or page in
// `.easterEggStage(host:) { finale }`, and add `.easterEggTrigger(taps:)` to whatever starts it.
// Everything marked falls under gravity, bouncing off each other, then the finale plays over the
// whole window with a Back button, and everything springs back into place.
//
// Inside Quarry the stage hands the effect to Quarry (`QuarryHost.playEasterEgg`), so Quarry's
// own window elements fall along with the tool's and the finale covers Quarry's whole window.
// On its own, the stage plays it in the tool's window.
//
// Everything here is a struct: QuarryKit is compiled into both Quarry and each tool.

private let log = Logger(subsystem: "io.github.pzmuv1517.QuarryKit", category: "easter-egg")

extension View {
    /// Lets an easter egg knock this view down. Mark leaf elements only; nested ones overlap.
    public func fallable(_ id: String) -> some View {
        modifier(Fallable(id: id))
    }

    /// Where an easter egg can play. Pass the `QuarryHost` when running inside Quarry. `finale`
    /// is shown full window after the fall; it calls `done` to end early (e.g. when a clip ends).
    public func easterEggStage<Finale: View>(
        host: QuarryHost? = nil,
        @ViewBuilder finale: @escaping @MainActor (_ done: @escaping () -> Void) -> Finale
    ) -> some View {
        modifier(EasterEggStage(host: host, finale: { AnyView(finale($0)) }))
    }

    /// Plays the stage's easter egg after `taps` clicks on this view within two seconds.
    public func easterEggTrigger(taps: Int = 5) -> some View {
        modifier(TapTrigger(taps: taps))
    }

    /// Moves this view by `move`. For hosts like Quarry moving their own elements.
    public func easterEggMove(_ move: FallMove?) -> some View {
        rotationEffect(.radians(move?.angle ?? 0))
            .offset(move?.offset ?? .zero)
            .zIndex(move == nil ? 0 : 1)
    }
}

/// Starts the easter egg of the enclosing stage.
public struct EasterEggAction {
    let run: @MainActor () -> Void

    @MainActor
    public func callAsFunction() { run() }
}

extension EnvironmentValues {
    @Entry public var easterEgg = EasterEggAction(run: {})
    @Entry var fallMoves: [String: FallMove] = [:]
}

/// How far a falling piece has moved from where it belongs.
public struct FallMove: Equatable, Sendable {
    public var offset: CGSize
    public var angle: Double

    public init(offset: CGSize, angle: Double) {
        self.offset = offset
        self.angle = angle
    }

    /// From `[dx, dy, radians]`, as passed through `QuarryHost.playEasterEgg`.
    public init?(_ numbers: [NSNumber]) {
        guard numbers.count == 3 else { return nil }
        self.init(offset: CGSize(width: numbers[0].doubleValue, height: numbers[1].doubleValue), angle: numbers[2].doubleValue)
    }

    public var numbers: [NSNumber] {
        [NSNumber(value: offset.width), NSNumber(value: offset.height), NSNumber(value: angle)]
    }
}

/// The finale over the whole window, with a Back button in the top left.
public struct EasterEggFinale<Content: View>: View {
    let back: () -> Void
    @ViewBuilder var content: Content

    public init(back: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.back = back
        self.content = content()
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            Brand.black
            content
            Button(action: back) {
                Label("Back", systemImage: "chevron.left")
            }
            .glassButton()
            .background(Brand.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.top, 40)
            .padding(.leading, 20)
        }
        .ignoresSafeArea()
        .ferriteStyle()
    }
}

/// Plays a video file edge to edge, cropping to fill, and calls `onEnd` when it finishes or its
/// window closes (a closed window isn't always destroyed, and the audio would keep going).
public struct EasterEggClip: View {
    let url: URL
    let onEnd: () -> Void
    @State private var player: AVPlayer?
    @State private var view = WeakView()

    public init(url: URL, onEnd: @escaping () -> Void) {
        self.url = url
        self.onEnd = onEnd
    }

    public var body: some View {
        PlayerView(player: player) { view.view = $0 }
            .onAppear {
                let player = AVPlayer(url: url)
                self.player = player
                player.play()
            }
            .onDisappear { player?.pause() }
            .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
                if let item = note.object as? AVPlayerItem, item === player?.currentItem { onEnd() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
                guard let window = note.object as? NSWindow, window === view.view?.window else { return }
                player?.pause()
                onEnd()
            }
    }

    /// A plain video layer. AppKit's AVPlayerView would hide the window's title bar buttons.
    private struct PlayerView: NSViewRepresentable {
        let player: AVPlayer?
        let found: (NSView) -> Void

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            view.wantsLayer = true
            let layer = AVPlayerLayer()
            layer.videoGravity = .resizeAspectFill
            layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            view.layer?.addSublayer(layer)
            DispatchQueue.main.async { found(view) }
            return view
        }

        func updateNSView(_ view: NSView, context: Context) {
            guard let layer = view.layer?.sublayers?.first as? AVPlayerLayer else { return }
            layer.frame = view.bounds
            if layer.player !== player { layer.player = player }
        }
    }
}

// MARK: - Stage

private struct FallableFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct Fallable: ViewModifier {
    let id: String
    @Environment(\.fallMoves) private var moves

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { geometry in
                Color.clear.preference(key: FallableFrames.self, value: [id: geometry.frame(in: .named(EasterEggStage.space))])
            })
            .easterEggMove(moves[id])
    }
}

private struct WeakView {
    weak var view: NSView?
}

private struct EasterEggStage: ViewModifier {
    static let space = "quarry.easterEgg"

    let host: QuarryHost?
    let finale: @MainActor (@escaping () -> Void) -> AnyView
    @State private var frames: [String: CGRect] = [:]
    @State private var anchor = WeakView()
    @State private var moves: [String: FallMove] = [:]
    @State private var isPlaying = false
    @State private var showsFinale = false

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(!isPlaying)
            .coordinateSpace(name: Self.space)
            .onPreferenceChange(FallableFrames.self) { frames = $0 }
            .background(ViewProbe { anchor.view = $0 })
            .environment(\.fallMoves, moves)
            .environment(\.solidGlass, isPlaying)
            .overlay {
                if showsFinale {
                    EasterEggFinale(back: back) { finale(back).ignoresSafeArea() }.transition(.opacity)
                }
            }
            .environment(\.easterEgg, EasterEggAction(run: play))
    }

    private func play() {
        guard !isPlaying, !frames.isEmpty else { return }
        isPlaying = true
        if playInHost() { return }

        let floor = anchor.view?.bounds.height ?? 900
        let frames = frames
        Task {
            var simulation = FallSimulation(frames: frames, floor: floor)
            while !simulation.isDone {
                simulation.step(FallSimulation.tick)
                moves = simulation.moves
                try? await Task.sleep(for: .seconds(FallSimulation.tick))
            }
            withAnimation(.easeOut(duration: 0.4)) { showsFinale = true }
        }
    }

    /// Inside Quarry, Quarry plays it across its whole window. False if there's no host that can.
    private func playInHost() -> Bool {
        guard let host, let stage = anchor.view, let content = stage.window?.contentView else { return false }
        // The pieces in the window's content view, origin at the top left.
        let inContent = stage.convert(stage.bounds, to: content)
        let origin = CGPoint(x: inContent.minX, y: content.isFlipped ? inContent.minY : content.bounds.height - inContent.maxY)
        let pieces = frames.mapValues { NSValue(rect: $0.offsetBy(dx: origin.x, dy: origin.y)) }

        let played: Void? = host.playEasterEgg?(
            pieces: pieces,
            move: { numbers in
                if numbers.isEmpty {
                    putBack()
                } else {
                    moves = numbers.compactMapValues(FallMove.init)
                }
            },
            finale: { done in
                // Edge to edge, under the title bar too, like the rest of the finale.
                let controller = NSHostingController(rootView: finale(done).ignoresSafeArea().ferriteStyle())
                controller.safeAreaRegions = []
                return controller
            }
        )
        if played == nil { log.info("Easter egg: this Quarry can't play it, playing in place") }
        return played != nil
    }

    private func back() {
        withAnimation(.easeOut(duration: 0.3)) { showsFinale = false }
        putBack()
    }

    private func putBack() {
        withAnimation(.spring(duration: 0.8, bounce: 0.25)) { moves = [:] }
        // Glass stays solid until the cards have settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { isPlaying = false }
    }
}

/// Hands over the NSView it's placed in.
private struct ViewProbe: NSViewRepresentable {
    let found: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { found(view) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

private struct TapTrigger: ViewModifier {
    let taps: Int
    @State private var times: [Date] = []
    @Environment(\.easterEgg) private var easterEgg

    func body(content: Content) -> some View {
        content.onTapGesture {
            let now = Date()
            times = times.filter { now.timeIntervalSince($0) < 2 } + [now]
            if times.count >= taps {
                times = []
                easterEgg()
            }
        }
    }
}

// MARK: - Physics

/// Boxes falling under gravity and bouncing off each other (rotation is cosmetic). The top ones
/// let go first and land on the ones below before those drop too.
public struct FallSimulation {
    /// Seconds per step.
    public static let tick = 1.0 / 120

    private struct Body {
        let id: String
        let home: CGRect
        var center: CGPoint
        var velocity: CGVector
        var angle: Double
        var spin: Double
        let releaseAt: Double
    }

    private var bodies: [Body]
    private var elapsed = 0.0
    private let floor: Double
    public private(set) var moves: [String: FallMove] = [:]

    /// `frames` in one coordinate space with y down; `floor` is the bottom of the window in it.
    public init(frames: [String: CGRect], floor: CGFloat) {
        self.floor = Double(floor)
        bodies = frames.sorted { $0.value.minY < $1.value.minY }.enumerated().map { index, entry in
            Body(
                id: entry.key,
                home: entry.value,
                center: CGPoint(x: entry.value.midX, y: entry.value.midY),
                velocity: CGVector(dx: .random(in: -90...90), dy: .random(in: -260...(-60))),
                angle: 0,
                spin: .random(in: -2.5...2.5) * Self.spinScale(entry.value.size),
                releaseAt: Double(index) * 0.07 + .random(in: 0...0.12)
            )
        }
    }

    /// Everything has fallen out of the window, or it's taking too long.
    public var isDone: Bool {
        elapsed > 8 || bodies.allSatisfy { $0.center.y - $0.home.height / 2 > floor + 40 }
    }

    /// Big pieces turn slowly, like heavier objects would.
    private static func spinScale(_ size: CGSize) -> Double {
        min(1, 140 / max(size.width, size.height, 1))
    }

    public mutating func step(_ dt: Double) {
        elapsed += dt
        for i in bodies.indices where elapsed >= bodies[i].releaseAt {
            bodies[i].velocity.dy += 2400 * dt
            bodies[i].center.x += bodies[i].velocity.dx * dt
            bodies[i].center.y += bodies[i].velocity.dy * dt
            bodies[i].angle += bodies[i].spin * dt
        }
        collide()
        moves = Dictionary(uniqueKeysWithValues: bodies.map { body in
            (body.id, FallMove(
                offset: CGSize(width: body.center.x - body.home.midX, height: body.center.y - body.home.midY),
                angle: body.angle
            ))
        })
    }

    /// Box-against-box collisions. Bodies that haven't let go yet are immovable, so falling
    /// pieces bounce off and pile onto them.
    private mutating func collide() {
        let restitution = 0.35
        for i in bodies.indices {
            for j in bodies.indices where j > i {
                let aMoving = elapsed >= bodies[i].releaseAt
                let bMoving = elapsed >= bodies[j].releaseAt
                guard aMoving || bMoving else { continue }
                let a = bodies[i], b = bodies[j]
                let dx = b.center.x - a.center.x
                let dy = b.center.y - a.center.y
                let overlapX = (a.home.width + b.home.width) / 2 * 0.92 - abs(dx)
                let overlapY = (a.home.height + b.home.height) / 2 * 0.92 - abs(dy)
                guard overlapX > 0, overlapY > 0 else { continue }

                let alongX = overlapX < overlapY
                let sign: Double = (alongX ? dx : dy) >= 0 ? 1 : -1
                let depth = alongX ? overlapX : overlapY
                let share = aMoving && bMoving ? 0.5 : 1
                let relative = alongX ? b.velocity.dx - a.velocity.dx : b.velocity.dy - a.velocity.dy
                let impulse = relative * sign < 0 ? -(1 + restitution) * relative * share : 0

                if aMoving {
                    if alongX { bodies[i].center.x -= sign * depth * share } else { bodies[i].center.y -= sign * depth * share }
                    if alongX { bodies[i].velocity.dx -= impulse } else { bodies[i].velocity.dy -= impulse }
                    bodies[i].spin += .random(in: -1.5...1.5) * Self.spinScale(a.home.size)
                }
                if bMoving {
                    if alongX { bodies[j].center.x += sign * depth * share } else { bodies[j].center.y += sign * depth * share }
                    if alongX { bodies[j].velocity.dx += impulse } else { bodies[j].velocity.dy += impulse }
                    bodies[j].spin += .random(in: -1.5...1.5) * Self.spinScale(b.home.size)
                }
            }
        }
    }
}

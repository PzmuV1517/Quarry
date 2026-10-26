import AppKit
import ApplicationServices
import Observation
import QuarryKit

/// A tool from the catalog, whether or not it's installed, or Quarry itself.
@MainActor
@Observable
final class Tool: Identifiable {
    enum Phase: Equatable {
        case idle
        case checking
        case installing(String)
        case failed(String)
    }

    var entry: CatalogEntry
    /// Quarry itself: it updates like a tool but is never loaded.
    let isQuarry: Bool
    private(set) var appURL: URL?
    /// Listed in Quarry's config, so Quarry runs it instead of the app running on its own.
    var isManaged = false
    @ObservationIgnored private(set) var instance: QuarryTool?
    private(set) var pages: [QuarryPage] = []
    var isStarted = false
    var loadError: String?
    var releases: [Release] = []
    var phase: Phase = .idle
    var lastChecked: Date?

    nonisolated let id: String

    init(entry: CatalogEntry, isQuarry: Bool = false) {
        id = entry.id
        self.entry = entry
        self.isQuarry = isQuarry
        locate()
    }

    var name: String { entry.name }
    var isLoaded: Bool { instance != nil }

    /// Read from disk each time: `Bundle` caches Info.plist per path, which goes stale when an
    /// app is replaced.
    private var info: [String: Any] {
        guard let appURL else { return [:] }
        return NSDictionary(contentsOf: appURL.appendingPathComponent("Contents/Info.plist")) as? [String: Any] ?? [:]
    }

    var version: Version? { (info["CFBundleShortVersionString"] as? String).flatMap(Version.init) }
    var minimumVersion: Version? { entry.minimumVersion.flatMap(Version.init) }
    var needsAccessibility: Bool { info[QuarryInterface.accessibilityKey] as? Bool ?? false }

    /// Installed, but from before Quarry could run it.
    var isTooOld: Bool {
        guard let version, let minimumVersion else { return false }
        return version < minimumVersion
    }

    var icon: NSImage? { appURL.map { NSWorkspace.shared.icon(forFile: $0.path) } }

    var latest: Release? { releases.first { $0.version != nil && $0.zip != nil } }

    var updateAvailable: Bool {
        guard let latest = latest?.version, let version else { return false }
        return latest > version
    }

    var isBusy: Bool {
        switch phase {
        case .checking, .installing: true
        default: false
        }
    }

    var menuBarTitle: String? {
        guard isStarted, let title = instance?.menuBarTitle else { return nil }
        return title
    }

    /// Prefers the copy in /Applications over builds lying around elsewhere.
    func locate() {
        if isQuarry {
            appURL = Bundle.main.bundleURL
            return
        }
        let standard = URL(fileURLWithPath: "/Applications/\(name).app")
        if FileManager.default.fileExists(atPath: standard.path) {
            appURL = standard
        } else {
            appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        }
    }

    func attach(_ instance: QuarryTool) {
        self.instance = instance
        pages = instance.pages.compactMap(QuarryPage.init)
    }

    func state(of release: Release) -> ReleaseRow.State {
        if release.isLegacy {
            return .unavailable(label: entry.legacyNames?.first ?? "Old name",
                                reason: "Released under an older name. It can't be installed over \(name).")
        }
        guard let target = release.version, release.zip != nil else {
            return .unavailable(label: "No download", reason: "This release has no app attached.")
        }
        if target == version { return .installed }
        if !isQuarry, let minimumVersion, target < minimumVersion {
            return .unavailable(label: "Standalone only",
                                reason: "Made before Quarry could run \(name). Download it from GitHub to use it on its own.")
        }
        return .available(version.map { target < $0 } == true ? "Downgrade" : "Install")
    }
}

/// Every tool Quarry knows about, and installing, loading and updating them.
@MainActor
@Observable
final class ToolLibrary {
    private(set) var tools: [Tool]
    let quarry: Tool
    private(set) var config: QuarryHub.Config
    private(set) var accessibilityGranted = AXIsProcessTrusted()
    private(set) var configError: String?

    @ObservationIgnored let host = HostBridge()
    /// Something shown in the menu bar changed.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var accessibilityTimer: Timer?
    @ObservationIgnored private var updateTimer: Timer?

    init() {
        config = QuarryHub.readConfig()
        quarry = Tool(
            entry: CatalogEntry(id: QuarryHub.bundleIdentifier, name: "Quarry", summary: "", repository: "PzmuV1517/Quarry",
                                symbol: "diamond", minimumVersion: nil, legacyNames: nil),
            isQuarry: true
        )
        tools = Catalog.bundled().map { Tool(entry: $0) }
        for tool in tools { tool.isManaged = config.tools.contains(tool.id) }
        host.onChange = { [weak self] _ in self?.onChange?() }
    }

    var managed: [Tool] { tools.filter(\.isManaged) }
    var needsAccessibility: Bool { managed.contains(where: \.needsAccessibility) }
    var updatesAvailable: [Tool] { ([quarry] + managed).filter(\.updateAvailable) }

    func tool(_ id: String) -> Tool? {
        id == quarry.id ? quarry : tools.first { $0.id == id }
    }

    /// Loads and starts the managed tools and begins checking for updates.
    func launch() {
        managed.forEach(load)
        scheduleUpdateChecks()
        Task { await refreshCatalog() }
    }

    // MARK: - Adding and removing

    /// Takes over a tool: installs it (or a version new enough) if needed, stops the standalone
    /// app, and runs it inside Quarry from now on.
    func add(_ tool: Tool) async {
        if tool.appURL == nil || tool.isTooOld {
            if tool.releases.isEmpty { await check(tool) }
            let installable = tool.releases.first { release in
                guard case .available = tool.state(of: release) else { return false }
                return true
            }
            guard let release = installable else {
                // A failed check already says why.
                if tool.phase == .idle { tool.phase = .failed("No version of \(tool.name) works with Quarry yet.") }
                return
            }
            guard await place(release, of: tool) else { return }
        }
        tool.isManaged = true
        if !config.tools.contains(tool.id) { config.tools.append(tool.id) }
        saveConfig()
        load(tool)
        onChange?()
    }

    /// Stops managing a tool; it goes back to running as its own app.
    func letGo(_ tool: Tool) {
        tool.isManaged = false
        config.tools.removeAll { $0 == tool.id }
        saveConfig()
        guard let app = tool.appURL else { return }
        if tool.isLoaded {
            Releases.relaunch(Bundle.main.bundleURL, thenOpen: [app])
        } else {
            NSWorkspace.shared.open(app)
        }
    }

    /// Moves the tool to the Trash. Its own settings files are left alone.
    func uninstall(_ tool: Tool) {
        tool.isManaged = false
        config.tools.removeAll { $0 == tool.id }
        saveConfig()
        if let app = tool.appURL {
            NSRunningApplication.runningApplications(withBundleIdentifier: tool.id).forEach { $0.terminate() }
            do {
                try FileManager.default.trashItem(at: app, resultingItemURL: nil)
            } catch {
                tool.phase = .failed("Couldn't move \(tool.name) to the Trash: \(error.localizedDescription)")
                return
            }
        }
        let wasLoaded = tool.isLoaded
        tool.locate()
        if wasLoaded { Releases.relaunch(Bundle.main.bundleURL) }
        onChange?()
    }

    // MARK: - Loading

    private func load(_ tool: Tool) {
        guard !tool.isLoaded else { return }
        guard let app = tool.appURL else {
            tool.loadError = "\(tool.name) isn't installed."
            return
        }
        do {
            tool.attach(try ToolLoader.load(app, host: host))
            tool.loadError = nil
        } catch {
            tool.loadError = error.localizedDescription
            return
        }
        startWhenReady(tool)
    }

    private func startWhenReady(_ tool: Tool) {
        guard tool.isLoaded, !tool.isStarted else { return }
        if tool.needsAccessibility, !accessibilityGranted {
            waitForAccessibility()
            return
        }
        // Never run two copies: the standalone app quits first.
        let standalone = NSRunningApplication.runningApplications(withBundleIdentifier: tool.id)
        guard !standalone.isEmpty else { return start(tool) }
        standalone.forEach { $0.terminate() }
        Task {
            for _ in 0..<30 where standalone.contains(where: { !$0.isTerminated }) {
                try? await Task.sleep(for: .milliseconds(100))
            }
            standalone.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
            start(tool)
        }
    }

    private func start(_ tool: Tool) {
        guard !tool.isStarted, let instance = tool.instance else { return }
        tool.isStarted = true
        instance.start()
        onChange?()
    }

    private func waitForAccessibility() {
        guard accessibilityTimer == nil else { return }
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, AXIsProcessTrusted() else { return }
                self.accessibilityTimer?.invalidate()
                self.accessibilityTimer = nil
                self.accessibilityGranted = true
                self.managed.forEach(self.startWhenReady)
                self.onChange?()
            }
        }
        onChange?()
    }

    // MARK: - Updates

    func setAutoUpdate(_ on: Bool) {
        config.autoUpdate = on
        saveConfig()
    }

    func check(_ tool: Tool) async {
        guard !tool.isBusy else { return }
        tool.phase = .checking
        do {
            tool.releases = try await Releases.fetch(
                repository: tool.entry.repository, appName: tool.name, legacyNames: tool.entry.legacyNames ?? []
            )
            tool.lastChecked = Date()
            tool.phase = .idle
        } catch {
            tool.phase = .failed("Couldn't check for updates: \(error.localizedDescription)")
        }
        onChange?()
    }

    /// Installs `release`. A tool that's already running, and Quarry itself, take effect after
    /// Quarry restarts, which happens right away.
    func install(_ release: Release, of tool: Tool) async {
        guard await place(release, of: tool) else { return }
        if tool.isQuarry || tool.isLoaded {
            Releases.relaunch(Bundle.main.bundleURL)
        } else if tool.isManaged {
            load(tool)
        }
    }

    /// Downloads `release` and puts it where the tool lives, without restarting anything.
    private func place(_ release: Release, of tool: Tool) async -> Bool {
        let target = tool.appURL ?? URL(fileURLWithPath: "/Applications/\(tool.name).app")
        guard Releases.canReplace(target) else {
            tool.phase = .failed("Can't write to \(target.deletingLastPathComponent().path).")
            return false
        }
        tool.phase = .installing(release.tag)
        do {
            let app = try await Releases.download(
                release, appName: tool.name, bundleIdentifier: tool.id,
                team: Releases.teamIdentifier(of: Bundle.main.bundleURL)
            )
            try Releases.place(app, at: target)
            tool.locate()
            tool.phase = .idle
            return true
        } catch {
            tool.phase = .failed("Install failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Checks 20 seconds after launch and then every six hours. With automatic updates on, it
    /// installs everything new and restarts Quarry once.
    private func scheduleUpdateChecks() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAll() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            MainActor.assumeIsolated { self?.checkAll() }
        }
    }

    private func checkAll() {
        Task {
            for tool in [quarry] + managed where tool.appURL != nil {
                await check(tool)
            }
            guard config.autoUpdate else { return }
            var replaced = false
            for tool in managed where tool.updateAvailable {
                if let latest = tool.latest, await place(latest, of: tool) { replaced = true }
            }
            if quarry.updateAvailable, let latest = quarry.latest, Releases.canReplace(quarry.appURL!) {
                await install(latest, of: quarry)
            } else if replaced {
                Releases.relaunch(Bundle.main.bundleURL)
            }
        }
    }

    // MARK: - Catalog and config

    private func refreshCatalog() async {
        guard let entries = try? await Catalog.fetch() else { return }
        for entry in entries {
            if let tool = tools.first(where: { $0.id == entry.id }) {
                tool.entry = entry
            } else {
                let tool = Tool(entry: entry)
                tool.isManaged = config.tools.contains(entry.id)
                tools.append(tool)
            }
        }
    }

    private func saveConfig() {
        do {
            try QuarryHub.writeConfig(config)
            configError = nil
        } catch {
            configError = "Couldn't save \(QuarryHub.configURL.path): \(error.localizedDescription)"
        }
    }
}

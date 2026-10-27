import AppKit
import QuarryKit
import ServiceManagement
import SwiftUI

// MARK: - Library

/// Every tool in one place: what's installed (Quarry first), with updates, versions and
/// removal, then what else can be installed.
struct LibraryPage: View {
    let library: ToolLibrary
    let navigation: Navigation

    var body: some View {
        let more = library.tools.filter { !$0.isManaged }
        VStack(alignment: .leading, spacing: 24) {
            GlassSection(title: "Installed", info: "These run inside Quarry and update with it.") {
                ForEach([library.quarry] + library.managed) { tool in
                    if !tool.isQuarry { Divider() }
                    InstalledRow(library: library, navigation: navigation, tool: tool)
                }
            }

            if !more.isEmpty {
                GlassSection(title: "More Tools", info: "Install downloads a tool into Applications. Add takes over a copy you already have. Either way it then runs inside Quarry.") {
                    ForEach(more) { tool in
                        if tool.id != more.first?.id { Divider() }
                        CatalogRow(library: library, tool: tool)
                    }
                }
            }
        }
        .task {
            for tool in [library.quarry] + library.managed where tool.releases.isEmpty {
                await library.check(tool)
            }
        }
    }
}

/// An installed tool: version and update status, its versions on demand, and a menu for the
/// rest.
private struct InstalledRow: View {
    let library: ToolLibrary
    let navigation: Navigation
    let tool: Tool
    @State private var showsVersions = false
    @State private var confirmUninstall = false

    private var status: String {
        let version = tool.version.map { "Version \($0)" } ?? "Not installed"
        switch tool.phase {
        case .checking: return "\(version) · Checking…"
        case .installing(let tag): return "Installing \(tag)…"
        case .failed: return version
        case .idle:
            if tool.updateAvailable, let latest = tool.latest { return "\(version) · \(latest.tag) available" }
            return tool.lastChecked == nil ? version : "\(version) · Up to date"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                ToolIcon(tool: tool, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tool.name).font(.system(size: 15, weight: .heavy))
                    Text(verbatim: status).font(.callout).foregroundStyle(Brand.secondary)
                }
                Spacer(minLength: 12)
                if tool.isBusy {
                    ProgressView().controlSize(.small)
                } else if tool.updateAvailable, let latest = tool.latest {
                    Button("Update") { Task { await library.install(latest, of: tool) } }
                        .glassButton(prominent: true)
                        .help(tool.isQuarry ? "Installs \(latest.tag) and restarts Quarry." : "Installs \(latest.tag). Quarry restarts to load it.")
                }
                if let page = tool.pages.first {
                    Button("Open") { navigation.destination = .toolPage(tool.id, page.id) }
                        .glassButton()
                }
                Menu {
                    Button("Check for Updates") { Task { await library.check(tool) } }
                    Link("Open on GitHub", destination: URL(string: "https://github.com/\(tool.entry.repository)")!)
                    if !tool.isQuarry {
                        Divider()
                        Button("Run on Its Own") { library.letGo(tool) }
                        Button("Uninstall…", role: .destructive) { confirmUninstall = true }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(Brand.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(tool.isBusy)
            }

            ForEach([tool.loadError, failure].compactMap { $0 }, id: \.self) { problem in
                Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
            }

            Button { withAnimation(.easeOut(duration: 0.15)) { showsVersions.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(showsVersions ? 90 : 0))
                    Text("Versions")
                }
                .font(.caption)
                .foregroundStyle(Brand.tertiary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 58)

            if let android = tool.entry.android {
                PhonePanel(library: library, tool: tool, package: android.package)
                    .padding(.leading, 58)
            }

            if showsVersions {
                VStack(alignment: .leading, spacing: 12) {
                    if tool.releases.isEmpty {
                        Text(tool.phase == .checking ? "Loading…" : "No releases found").foregroundStyle(Brand.secondary)
                    }
                    ForEach(tool.releases) { release in
                        if release != tool.releases.first { Divider() }
                        ReleaseRow(release: release, state: tool.state(of: release), isBusy: tool.isBusy) {
                            Task { await library.install(release, of: tool) }
                        }
                    }
                }
                .padding(.leading, 58)
            }
        }
        .alert("Uninstall \(tool.name)?", isPresented: $confirmUninstall) {
            Button("Uninstall", role: .destructive) { library.uninstall(tool) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(tool.name) moves to the Trash and Quarry restarts. Its settings files stay.")
        }
    }

    private var failure: String? {
        if case .failed(let message) = tool.phase { message } else { nil }
    }
}

/// A tool's Android app on the phones plugged in over USB: which version each has, and
/// installing the latest release with adb.
private struct PhonePanel: View {
    let library: ToolLibrary
    let tool: Tool
    let package: String

    @State private var showsVersions = false
    @State private var pendingDowngrade: Release?

    private var phones: AndroidPhones { library.phones }
    /// Releases with an Android app, newest first.
    private var releases: [Release] { tool.releases.filter { $0.apk != nil && $0.version != nil } }
    private var latest: Release? { releases.first }
    /// The phone the versions list installs on: the first one ready.
    private var target: AndroidPhones.Phone? { phones.phones.first { $0.state == .ready } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "candybarphone")
                Text("ANDROID APP").font(.system(size: 10, weight: .bold)).tracking(1.4)
                InfoButton(text: "Plug your phone in over USB with USB debugging on (Settings → Developer options). Quarry installs the app with adb.")
                Spacer()
                Text(latest.map { "Latest \($0.tag)" } ?? "No release yet").font(.caption).foregroundStyle(Brand.tertiary)
            }
            .foregroundStyle(Brand.tertiary)

            if phones.adb == nil {
                Text("Needs adb. Install it with `brew install android-platform-tools`.")
                    .font(.callout)
                    .foregroundStyle(Brand.secondary)
                    .textSelection(.enabled)
            } else if phones.phones.isEmpty {
                Text("No phone plugged in.").font(.callout).foregroundStyle(Brand.secondary)
            }
            ForEach(phones.phones) { phone in
                if phone != phones.phones.first { Divider() }
                PhoneRow(phones: phones, phone: phone, package: package, latest: latest)
            }

            if !releases.isEmpty {
                Button { withAnimation(.easeOut(duration: 0.15)) { showsVersions.toggle() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(showsVersions ? 90 : 0))
                        Text("Android versions")
                    }
                    .font(.caption)
                    .foregroundStyle(Brand.tertiary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if showsVersions {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(releases) { release in
                        if release != releases.first { Divider() }
                        ReleaseRow(release: release, state: state(of: release), isBusy: target.map { phones.activity[$0.id] != nil } ?? true) {
                            install(release)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Brand.hairline))
        .alert("Install \(pendingDowngrade?.tag ?? "") on \(target?.model ?? "your phone")?",
               isPresented: Binding(get: { pendingDowngrade != nil }, set: { if !$0 { pendingDowngrade = nil } }),
               presenting: pendingDowngrade) { release in
            Button("Remove and Install", role: .destructive) { install(release, confirmed: true) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Android can't install an older version over a newer one, so the app is removed first. Its pairing goes with it: pair again afterwards.")
        }
        .task {
            // Notices phones being plugged in while the Library is open.
            while !Task.isCancelled {
                await phones.refresh(packages: [package])
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}

extension PhonePanel {
    /// How a release relates to what the plugged-in phone has.
    func state(of release: Release) -> ReleaseRow.State {
        guard let target else { return .unavailable(label: "No phone", reason: "Plug in your phone with USB debugging on.") }
        guard let version = release.version else { return .unavailable(label: "No version", reason: "This release has no version number.") }
        guard let installed = target.versions[package] else { return .available("Install") }
        if version == installed { return .installed }
        return .available(version < installed ? "Downgrade" : "Install")
    }

    func install(_ release: Release, confirmed: Bool = false) {
        guard let target else { return }
        if !confirmed, let version = release.version, let installed = target.versions[package], version < installed {
            pendingDowngrade = release
            return
        }
        Task { await phones.install(release, package: package, on: target) }
    }
}

private struct PhoneRow: View {
    let phones: AndroidPhones
    let phone: AndroidPhones.Phone
    let package: String
    let latest: Release?

    var body: some View {
        let installed = phone.versions[package]
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(phone.model).font(.system(size: 13, weight: .semibold))
                    Text(status(installed)).font(.caption).foregroundStyle(Brand.tertiary)
                }
                Spacer()
                if let activity = phones.activity[phone.id] {
                    ProgressView().controlSize(.small)
                    Text(activity).font(.caption).foregroundStyle(Brand.secondary)
                } else if phone.state == .ready {
                    if let latest, let version = latest.version, installed.map({ $0 < version }) ?? true {
                        Button(installed == nil ? "Install" : "Update") {
                            Task { await phones.install(latest, package: package, on: phone) }
                        }
                        .glassButton(prominent: true)
                    }
                }
            }
            if let problem = phones.problems[phone.id] {
                Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
            }
        }
    }

    private func status(_ installed: Version?) -> String {
        switch phone.state {
        case .unauthorized: return "Allow USB debugging on the phone"
        case .offline: return "Not responding"
        case .ready: return installed.map { "Version \($0) installed" } ?? "Not installed"
        }
    }
}

/// A tool that isn't in Quarry yet.
private struct CatalogRow: View {
    let library: ToolLibrary
    let tool: Tool

    var body: some View {
        HStack(spacing: 14) {
            ToolIcon(tool: tool, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(tool.name).font(.system(size: 15, weight: .heavy))
                    Link(destination: URL(string: "https://github.com/\(tool.entry.repository)")!) {
                        Image(systemName: "arrow.up.right").font(.caption2)
                    }
                    .foregroundStyle(Brand.tertiary)
                    .help("Open on GitHub")
                }
                Text(tool.entry.summary).font(.callout).foregroundStyle(Brand.secondary)
                Text(status).font(.caption).foregroundStyle(isFailed ? .orange : Brand.tertiary)
            }
            Spacer(minLength: 12)
            if tool.isBusy {
                ProgressView().controlSize(.small)
            } else {
                Button(tool.appURL == nil ? "Install" : "Add") { Task { await library.add(tool) } }
                    .glassButton(prominent: true)
            }
        }
    }

    private var isFailed: Bool {
        if case .failed = tool.phase { true } else { false }
    }

    private var status: String {
        switch tool.phase {
        case .checking: return "Checking…"
        case .installing(let tag): return "Installing \(tag)…"
        case .failed(let message): return message
        case .idle:
            guard let version = tool.version else { return "Not installed" }
            if tool.isTooOld { return "Version \(version) runs on its own. Adding updates it first." }
            return "Version \(version) runs on its own"
        }
    }
}

/// The installed app's icon, or the catalog's symbol on a dark tile.
struct ToolIcon: View {
    let tool: Tool
    let size: CGFloat

    var body: some View {
        if let icon = tool.icon {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.17), Brand.black], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).strokeBorder(Brand.hairline))
                .overlay(Image(systemName: tool.entry.symbol).font(.system(size: size * 0.42)).foregroundStyle(Brand.secondary))
                .frame(width: size * 0.82, height: size * 0.82)
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Updates (a tool's or Quarry's own)

struct ToolUpdatesPage: View {
    let library: ToolLibrary
    let tool: Tool
    @State private var confirmUninstall = false

    private var status: String {
        switch tool.phase {
        case .checking: return "Checking…"
        case .installing(let tag): return "Installing \(tag)…"
        default:
            if tool.updateAvailable, let latest = tool.latest { return "\(latest.tag) is available" }
            if tool.lastChecked != nil { return "Up to date" }
            return tool.version.map { "Version \($0)" } ?? "Not installed"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                ToolIcon(tool: tool, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.name).font(.system(size: 22, weight: .heavy))
                    Text(verbatim: tool.version.map { "Version \($0)" } ?? "Not installed").foregroundStyle(Brand.secondary)
                }
            }

            if let error = tool.loadError {
                GlassSection(title: "Problems") {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
                }
            }

            GlassSection(title: "Updates", info: tool.isQuarry
                         ? "Installing restarts Quarry."
                         : "Installing restarts Quarry, which restarts \(tool.name).") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(status)
                        if let checked = tool.lastChecked {
                            Text("Checked \(checked.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundStyle(Brand.tertiary)
                        }
                    }
                    Spacer()
                    if tool.updateAvailable, let latest = tool.latest {
                        Button("Install \(latest.tag)") { Task { await library.install(latest, of: tool) } }
                            .glassButton(prominent: true)
                            .disabled(tool.isBusy)
                    }
                    Button("Check Now") { Task { await library.check(tool) } }
                        .glassButton()
                        .disabled(tool.isBusy)
                }
            }

            GlassSection(title: "Versions") {
                if tool.releases.isEmpty {
                    Text(tool.phase == .checking ? "Loading…" : "No releases found").foregroundStyle(Brand.secondary)
                }
                ForEach(tool.releases) { release in
                    if release != tool.releases.first { Divider() }
                    ReleaseRow(release: release, state: tool.state(of: release), isBusy: tool.isBusy) {
                        Task { await library.install(release, of: tool) }
                    }
                }
            }

            if !tool.isQuarry, tool.isManaged {
                GlassSection(title: "Manage") {
                    Row(title: "Run on its own", info: "Quarry stops running \(tool.name). It gets its own menu bar icon and settings window back.") {
                        Button("Let Go") { library.letGo(tool) }.glassButton()
                    }
                    Divider()
                    Row(title: "Uninstall", info: "Moves \(tool.name) to the Trash. Its settings files stay.") {
                        Button("Uninstall…") { confirmUninstall = true }.glassButton()
                    }
                }
            }

            if case .failed(let message) = tool.phase {
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
            }
        }
        .task {
            if tool.releases.isEmpty { await library.check(tool) }
        }
        .alert("Uninstall \(tool.name)?", isPresented: $confirmUninstall) {
            Button("Uninstall", role: .destructive) { library.uninstall(tool) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(tool.name) moves to the Trash and Quarry restarts.")
        }
    }
}

// MARK: - Settings

struct SettingsPage: View {
    let library: ToolLibrary
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var accessibility = AXIsProcessTrusted()
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            GlassSection(title: "General") {
                Row(title: "Open at login", info: "Only works from the Applications folder.") {
                    Toggle("", isOn: $launchAtLogin).toggleStyle(.switch).labelsHidden()
                }
                Divider()
                Row(title: "Install updates automatically", info: "Checks GitHub every 6 hours for Quarry and its tools. Quarry restarts after installing.") {
                    Toggle("", isOn: Binding(get: { library.config.autoUpdate }, set: { library.setAutoUpdate($0) }))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            GlassSection(title: "Permissions") {
                Row(title: "Accessibility", info: "Needed by tools that move windows, like Spinel. Quarry asks once for all of them.") {
                    if accessibility {
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(Brand.secondary)
                    } else {
                        Button("Open Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                        .glassButton()
                    }
                }
            }

            GlassSection(title: "Config File", info: "Lists the tools Quarry runs. Each tool keeps its own settings file.") {
                Text(QuarryHub.configURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([QuarryHub.configURL]) }
                    .glassButton()
            }

            AboutQuarry()

            ForEach([loginError, library.configError].compactMap { $0 }, id: \.self) { problem in
                Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
            }
        }
        .onChange(of: launchAtLogin) { _, on in
            let service = SMAppService.mainApp
            do {
                if on, service.status != .enabled { try service.register() }
                if !on, service.status == .enabled { try service.unregister() }
                loginError = nil
            } catch {
                loginError = "Open at login: \(error.localizedDescription)"
            }
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            accessibility = AXIsProcessTrusted()
        }
    }
}

// MARK: - About

/// Quarry's credits, at the bottom of Settings.
private struct AboutQuarry: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    var body: some View {
        GlassSection(title: "About") {
            HStack(spacing: 14) {
                AppIcon(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quarry").font(.system(size: 17, weight: .heavy))
                    Text("Version \(version) · © \(Credits.year) \(Credits.author)").font(.callout).foregroundStyle(Brand.secondary)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Fact("GitHub", "@\(Credits.github)", link: Credits.profile)
                Fact("Source", "github.com/\(Credits.github)/Quarry", link: Credits.repository("Quarry"))
                Fact("Bugs", "Open an issue", link: Credits.repository("Quarry").appendingPathComponent("issues"))
            }
            .padding(.horizontal, -14)
            .padding(.vertical, -8)
        }
    }
}

import AppKit
import Security

/// A GitHub release of an app.
public struct Release: Identifiable, Equatable, Sendable {
    public let id: Int
    public let tag: String
    public let version: Version?
    public let notes: String
    public let date: Date?
    /// The zipped app, if the release has one.
    public let zip: URL?
    /// The tool's Android app (`<appName>…apk`), if it has one.
    public let apk: URL?
    public let page: URL
    /// Published under an older name: listed for history, never installable.
    public let isLegacy: Bool

    public init(id: Int, tag: String, version: Version?, notes: String, date: Date?, zip: URL?, apk: URL? = nil, page: URL, isLegacy: Bool) {
        self.id = id
        self.tag = tag
        self.version = version
        self.notes = notes
        self.date = date
        self.zip = zip
        self.apk = apk
        self.page = page
        self.isLegacy = isLegacy
    }
}

public struct ReleaseError: LocalizedError {
    public let errorDescription: String?
    public init(_ message: String) { errorDescription = message }
}

/// Lists, downloads and installs releases. An app is installed only if it has the expected bundle
/// identifier and is signed by the same team as the running app.
public enum Releases {
    /// Releases of `repository` ("owner/name"), newest first. The app is the asset named
    /// `<appName>…zip`; releases with only a `<legacy name>…zip` are marked `isLegacy`.
    public static func fetch(repository: String, appName: String, legacyNames: [String] = []) async throws -> [Release] {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ReleaseError("GitHub returned \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        return try parse(data, appName: appName, legacyNames: legacyNames)
    }

    public static func parse(_ data: Data, appName: String, legacyNames: [String] = []) throws -> [Release] {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        struct Item: Decodable {
            let id: Int
            let tag_name: String
            let body: String?
            let published_at: Date?
            let html_url: URL
            let draft: Bool
            let assets: [Asset]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Item].self, from: data)
            .filter { !$0.draft }
            .map { item in
                let zip = item.assets.first { $0.name.hasPrefix(appName) && $0.name.hasSuffix(".zip") }
                return Release(
                    id: item.id,
                    tag: item.tag_name,
                    version: Version(item.tag_name),
                    notes: item.body ?? "",
                    date: item.published_at,
                    zip: zip?.browser_download_url,
                    apk: item.assets.first { $0.name.hasPrefix(appName) && $0.name.hasSuffix(".apk") }?.browser_download_url,
                    page: item.html_url,
                    isLegacy: zip == nil && item.assets.contains { asset in legacyNames.contains { asset.name.hasPrefix($0) } }
                )
            }
            .sorted { ($0.version ?? Version("0")!) > ($1.version ?? Version("0")!) }
    }

    /// Downloads and unpacks `release`, returning `<appName>.app` in a temporary folder. Checks
    /// the bundle identifier and that it's signed by `team` (see `teamIdentifier(of:)`).
    public static func download(_ release: Release, appName: String, bundleIdentifier: String, team: String?) async throws -> URL {
        guard let zip = release.zip else { throw ReleaseError("\(release.tag) has no download") }
        let (download, _) = try await URLSession.shared.download(from: zip)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("\(appName)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let archive = work.appendingPathComponent("download.zip")
        try FileManager.default.moveItem(at: download, to: archive)

        let app = try await Task.detached {
            try run("/usr/bin/ditto", ["-x", "-k", archive.path, work.path])
            let app = work.appendingPathComponent("\(appName).app")
            guard FileManager.default.fileExists(atPath: app.path) else { throw ReleaseError("The download has no \(appName).app") }
            guard Bundle(url: app)?.bundleIdentifier == bundleIdentifier else { throw ReleaseError("The download is a different app") }
            return app
        }.value

        guard let team, teamIdentifier(of: app) == team else {
            throw ReleaseError("The download isn't signed by the same developer")
        }
        return app
    }

    /// Moves `newApp` to `target`, replacing whatever is there.
    public static func place(_ newApp: URL, at target: URL) throws {
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: newApp)
        } else {
            try FileManager.default.moveItem(at: newApp, to: target)
        }
    }

    /// Whether an app at `url` could be replaced in place.
    public static func canReplace(_ url: URL) -> Bool {
        url.pathExtension == "app" && FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path)
    }

    /// Quits and reopens `app` (normally the running one) a second later.
    @MainActor
    public static func relaunch(_ app: URL, thenOpen others: [URL] = []) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", #"sleep 1; for app in "$@"; do /usr/bin/open "$app"; done"#, "sh"] + ([app] + others).map(\.path)
        try? process.run()
        NSApp.terminate(nil)
    }

    /// The signing team of a validly signed app, or nil.
    public static func teamIdentifier(of app: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil) == errSecSuccess
        else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ReleaseError("\(tool) failed") }
    }
}

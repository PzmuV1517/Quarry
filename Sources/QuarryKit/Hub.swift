import AppKit

/// What a tool needs to know about Quarry when it runs as its own app.
///
/// Quarry lists the tools it manages in its config file. A tool launched from Finder, Spotlight or
/// a login item checks `manages(_:)` first: if Quarry has taken it over, it opens Quarry on its
/// page and quits rather than running a second copy. Once Quarry is gone, or lets the tool go,
/// the tool runs on its own again.
public enum QuarryHub {
    public static let bundleIdentifier = "io.github.pzmuv1517.Quarry"
    public static let configURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/quarry/config.json")

    public struct Config: Codable, Equatable, Sendable {
        /// Bundle identifiers of the tools Quarry runs.
        public var tools: [String] = []
        /// Install updates for Quarry and its tools without asking.
        public var autoUpdate = true

        public init() {}

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            tools = try container.decodeIfPresent([String].self, forKey: .tools) ?? []
            autoUpdate = try container.decodeIfPresent(Bool.self, forKey: .autoUpdate) ?? true
        }
    }

    public static func readConfig() -> Config {
        guard let data = try? Data(contentsOf: configURL) else { return Config() }
        return (try? JSONDecoder().decode(Config.self, from: data)) ?? Config()
    }

    public static func writeConfig(_ config: Config) throws {
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: configURL, options: .atomic)
    }

    /// Whether Quarry runs this tool, so the standalone app should step aside.
    public static func manages(_ bundleIdentifier: String) -> Bool {
        readConfig().tools.contains(bundleIdentifier)
            && NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) != nil
    }

    /// `quarry://tool/<bundle id>[/<page>]`, which opens Quarry on that tool.
    public static func url(tool: String, page: String? = nil) -> URL {
        URL(string: "quarry://tool/\(tool)" + (page.map { "/\($0)" } ?? ""))!
    }

    /// Opens Quarry, launching it if needed, on the tool's page.
    public static func show(tool: String, page: String? = nil) {
        NSWorkspace.shared.open(url(tool: tool, page: page))
    }
}

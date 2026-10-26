import Foundation

/// A tool Quarry can install, as listed in `catalog.json`.
struct CatalogEntry: Codable, Identifiable, Hashable {
    /// The app's bundle identifier.
    let id: String
    let name: String
    let summary: String
    /// GitHub "owner/name". Releases carry `<name>-<version>.zip` with `<name>.app` inside.
    let repository: String
    /// SF Symbol shown until the app is installed.
    let symbol: String
    /// The first version Quarry can run. Older ones only work on their own.
    let minimumVersion: String?
    /// Names the app was released under before.
    let legacyNames: [String]?
}

enum Catalog {
    /// The live list, so new tools show up without a Quarry update.
    static let remote = URL(string: "https://raw.githubusercontent.com/PzmuV1517/Quarry/main/catalog.json")!

    private struct File: Codable { let tools: [CatalogEntry] }

    /// The copy shipped inside Quarry.app, used until the live one loads.
    static func bundled() -> [CatalogEntry] {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let tools = try? decode(data)
        else { return [] }
        return tools
    }

    static func fetch() async throws -> [CatalogEntry] {
        var request = URLRequest(url: remote)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, _) = try await URLSession.shared.data(for: request)
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> [CatalogEntry] {
        try JSONDecoder().decode(File.self, from: data).tools
    }
}

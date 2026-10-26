import XCTest
@testable import QuarryKit

final class VersionTests: XCTestCase {
    func testParsesAndCompares() {
        XCTAssertEqual(Version("v0.2.0")?.description, "0.2.0")
        XCTAssertNil(Version("v0.2-beta"))
        XCTAssertNil(Version(""))
        XCTAssertLessThan(Version("0.1.1")!, Version("v0.2.0")!)
        XCTAssertLessThan(Version("0.9")!, Version("0.10")!)
        XCTAssertEqual(Version("1.0")!, Version("1.0.0")!)
        XCTAssertFalse(Version("1.2.0")! < Version("1.1.9")!)
    }
}

final class ReleasesTests: XCTestCase {
    func testParsesAppAndLegacyAssets() throws {
        let json = """
        [
          {"id": 1, "tag_name": "v0.1.0", "body": "old", "published_at": "2026-10-20T10:00:00Z",
           "html_url": "https://github.com/a/b/releases/1", "draft": false,
           "assets": [{"name": "TileMyMac-0.1.0.zip", "browser_download_url": "https://example.com/t.zip"}]},
          {"id": 2, "tag_name": "v0.4.0", "body": null, "published_at": "2026-10-27T10:00:00Z",
           "html_url": "https://github.com/a/b/releases/2", "draft": false,
           "assets": [{"name": "Spinel-0.4.0.zip", "browser_download_url": "https://example.com/s.zip"}]},
          {"id": 3, "tag_name": "v0.5.0", "body": "", "published_at": null,
           "html_url": "https://github.com/a/b/releases/3", "draft": true, "assets": []}
        ]
        """
        let releases = try Releases.parse(Data(json.utf8), appName: "Spinel", legacyNames: ["TileMyMac"])
        XCTAssertEqual(releases.map(\.tag), ["v0.4.0", "v0.1.0"])  // newest first, drafts dropped
        XCTAssertEqual(releases[0].zip?.absoluteString, "https://example.com/s.zip")
        XCTAssertFalse(releases[0].isLegacy)
        XCTAssertNil(releases[1].zip)
        XCTAssertTrue(releases[1].isLegacy)
    }
}

final class HubTests: XCTestCase {
    func testConfigDefaultsMissingKeys() throws {
        let config = try JSONDecoder().decode(QuarryHub.Config.self, from: Data(#"{"tools": ["x"]}"#.utf8))
        XCTAssertEqual(config.tools, ["x"])
        XCTAssertTrue(config.autoUpdate)
    }

    func testToolURL() {
        XCTAssertEqual(QuarryHub.url(tool: "io.example.Tool", page: "layout").absoluteString, "quarry://tool/io.example.Tool/layout")
        XCTAssertEqual(QuarryHub.url(tool: "io.example.Tool").absoluteString, "quarry://tool/io.example.Tool")
    }

    func testPageRoundTrip() {
        let page = QuarryPage(id: "general", title: "General", symbol: "gearshape")
        XCTAssertEqual(QuarryPage(page.dictionary), page)
        XCTAssertNil(QuarryPage(["title": "No id"]))
    }
}

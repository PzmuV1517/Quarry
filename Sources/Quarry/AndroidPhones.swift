import Foundation
import Observation
import QuarryKit

/// Android phones plugged in over USB, through adb: which have a tool's Android app, and
/// installing it from the tool's latest release.
@MainActor
@Observable
final class AndroidPhones {
    struct Phone: Identifiable, Equatable {
        enum State: Equatable {
            case ready
            /// USB debugging hasn't been allowed for this Mac on the phone yet.
            case unauthorized
            case offline
        }

        /// adb's serial number.
        let id: String
        let model: String
        let state: State
        /// Installed version of each package asked about, nil if not installed.
        var versions: [String: Version] = [:]
    }

    /// adb, if it's installed.
    let adb: URL? = AndroidPhones.findADB()
    private(set) var phones: [Phone] = []
    /// What's happening on each phone, by serial.
    private(set) var activity: [String: String] = [:]
    private(set) var problems: [String: String] = [:]

    private static func findADB() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            ProcessInfo.processInfo.environment["ANDROID_HOME"].map { "\($0)/platform-tools/adb" },
            "\(home)/Library/Android/sdk/platform-tools/adb",
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }

    /// Lists phones and which version of each of `packages` they have.
    func refresh(packages: [String]) async {
        guard adb != nil, let output = try? await run(["devices", "-l"]) else { return }
        var found = output.split(separator: "\n").dropFirst().compactMap(Self.phone)
        for index in found.indices where found[index].state == .ready {
            for package in packages {
                let dump = (try? await run(["-s", found[index].id, "shell", "dumpsys", "package", package])) ?? ""
                if let version = Self.versionName(in: dump) { found[index].versions[package] = version }
            }
        }
        phones = found
    }

    /// Downloads `release`'s APK and installs it on `phone`, keeping the app's data.
    func install(_ release: Release, package: String, on phone: Phone) async {
        guard let apk = release.apk else { return }
        await installing(release.tag, package: package, on: phone) {
            let (download, _) = try await URLSession.shared.download(from: apk)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).apk")
            try FileManager.default.moveItem(at: download, to: file)
            defer { try? FileManager.default.removeItem(at: file) }
            try await self.adbInstall(file, on: phone)
        }
    }

    private func installing(_ what: String, package: String, on phone: Phone, _ work: () async throws -> Void) async {
        activity[phone.id] = "Installing \(what)…"
        problems[phone.id] = nil
        do {
            try await work()
            await refresh(packages: [package])
        } catch {
            problems[phone.id] = "Couldn't install: \(error.localizedDescription)"
        }
        activity[phone.id] = nil
    }

    private func adbInstall(_ file: URL, on phone: Phone) async throws {
        let output = try await run(["-s", phone.id, "install", "-r", file.path])
        if !output.contains("Success") {
            throw ReleaseError(output.split(separator: "\n").last.map(String.init) ?? "adb install failed")
        }
    }

    // MARK: - Parsing adb

    /// A line of `adb devices -l`, like `R5CT10 device usb:1-1 product:x model:Pixel_8 device:shiba`.
    static func phone(_ line: Substring) -> Phone? {
        let fields = line.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 2 else { return nil }
        let state: Phone.State = switch fields[1] {
        case "device": .ready
        case "unauthorized": .unauthorized
        default: .offline
        }
        let model = fields.first { $0.hasPrefix("model:") }.map { $0.dropFirst(6).replacingOccurrences(of: "_", with: " ") }
        return Phone(id: String(fields[0]), model: model ?? String(fields[0]), state: state)
    }

    /// `versionName=0.1.0` in `dumpsys package`.
    static func versionName(in dump: String) -> Version? {
        guard let range = dump.range(of: "versionName=") else { return nil }
        let rest = dump[range.upperBound...].prefix { !$0.isWhitespace }
        return Version(String(rest))
    }

    private func run(_ arguments: [String]) async throws -> String {
        guard let adb else { throw ReleaseError("adb isn't installed") }
        return try await Task.detached {
            let process = Process()
            process.executableURL = adb
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }.value
    }
}

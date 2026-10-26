// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Quarry",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Quarry", targets: ["Quarry"]),
        // What tools build against: the interface Quarry loads them through and the shared look.
        .library(name: "QuarryKit", targets: ["QuarryKit"]),
    ],
    targets: [
        .target(name: "QuarryKit"),
        // The hub: menu bar, settings window, installing and loading tools.
        .executableTarget(name: "Quarry", dependencies: ["QuarryKit"]),
        .testTarget(name: "QuarryKitTests", dependencies: ["QuarryKit"]),
    ],
    swiftLanguageModes: [.v5]
)

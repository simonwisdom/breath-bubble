// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BreathFloat",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "BreathFloat", path: "Sources/BreathFloat")
    ]
)

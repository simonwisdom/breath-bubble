// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BreathBubble",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "BreathBubble", path: "Sources/BreathBubble")
    ]
)

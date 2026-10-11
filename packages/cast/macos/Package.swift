// swift-tools-version: 5.9
// Test-only manifest: `swift test` runs AirPlayEngine's tests without Flutter.
// The plugin itself builds through cast.podspec.
import PackageDescription

let package = Package(
    name: "cast",
    platforms: [.macOS("12.0")],
    targets: [
        .target(name: "AirPlayCore", path: "Classes", exclude: ["CastPlugin.swift"]),
        .testTarget(name: "AirPlayTests", dependencies: ["AirPlayCore"], path: "Tests/AirPlayTests"),
    ]
)

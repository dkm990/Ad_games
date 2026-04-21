// swift-tools-version:5.9
import PackageDescription

/// Lightweight SwiftPM shim over the platform-agnostic slice of the game.
/// The real app is built by `AdGamesPrototype.xcodeproj`; this package exists so
/// the reducer/config/persistence logic can be `swift test`-ed on any platform
/// (including Linux CI), without spinning up iOS Simulator.
let package = Package(
    name: "AdGamesCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "AdGamesCore", targets: ["AdGamesCore"]),
    ],
    targets: [
        .target(
            name: "AdGamesCore",
            path: ".",
            exclude: [
                "App",
                "Scene",
                "UI",
                "Config",
                "Docs",
                "AdGamesPrototype.xcodeproj",
                "Tests",
                "Package.swift",
            ],
            sources: [
                "Core",
                "Services",
            ]
        ),
        .testTarget(
            name: "AdGamesCoreTests",
            dependencies: ["AdGamesCore"],
            path: "Tests/AdGamesCoreTests"
        ),
    ]
)

// swift-tools-version: 6.0
import PackageDescription

// Tests de référence hors `GameScene` : moteur Watch et RNG du défi.
// L’analyseur iPhone dépend de `BlockType`, défini dans `GameScene.swift` :
// il est couvert par la cible Xcode `BlomixReferenceTests` (`@testable import BLOMIX`).
let package = Package(
    name: "BlomixReference",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "WatchEngine",
            path: "Watch/Engine"
        ),
        .target(
            name: "BlomixDailyRNG",
            path: "ReferenceSources"
        ),
        .testTarget(
            name: "BlomixReferenceTests",
            dependencies: ["WatchEngine", "BlomixDailyRNG"],
            path: "ReferenceTests"
        ),
    ]
)

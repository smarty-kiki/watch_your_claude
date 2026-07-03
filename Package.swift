// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "WatchYourClaude",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "WatchYourClaude",
            path: "Sources/WatchYourClaude",
            resources: [.copy("Resources/notification.wav"), .copy("Resources/icon.png")]
        ),
    ]
)

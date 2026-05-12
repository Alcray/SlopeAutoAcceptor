// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "VisionClicker",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "AgentAutoAcceptCore",
            targets: ["AgentAutoAcceptCore"]
        ),
        .executable(
            name: "VisionClicker",
            targets: ["VisionClicker"]
        ),
        .executable(
            name: "AgentAutoAcceptSelfTest",
            targets: ["AgentAutoAcceptSelfTest"]
        )
    ],
    targets: [
        .target(
            name: "AgentAutoAcceptCore"
        ),
        .executableTarget(
            name: "VisionClicker",
            path: "Sources/AgentAutoAccept"
        ),
        .executableTarget(
            name: "AgentAutoAcceptSelfTest",
            dependencies: ["AgentAutoAcceptCore"],
            path: "Tests/AgentAutoAcceptTests"
        )
    ]
)

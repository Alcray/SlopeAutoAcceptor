// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AgentAutoAccept",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "AgentAutoAcceptCore",
            targets: ["AgentAutoAcceptCore"]
        ),
        .executable(
            name: "AgentAutoAccept",
            targets: ["AgentAutoAccept"]
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
            name: "AgentAutoAccept",
            dependencies: ["AgentAutoAcceptCore"]
        ),
        .executableTarget(
            name: "AgentAutoAcceptSelfTest",
            dependencies: ["AgentAutoAcceptCore"],
            path: "Tests/AgentAutoAcceptTests"
        )
    ]
)

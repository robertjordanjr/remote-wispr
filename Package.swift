// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RemoteWispr",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "RemoteWisprCore",
            targets: ["RemoteWisprCore"]
        ),
        .executable(
            name: "remote-wispr-spike",
            targets: ["RemoteWisprSpike"]
        ),
        .executable(
            name: "remote-wispr-fixture-tests",
            targets: ["RemoteWisprFixtureTests"]
        ),
        .executable(
            name: "remote-wispr-donor-app",
            targets: ["RemoteWisprDonorApp"]
        ),
        .executable(
            name: "remote-wispr-menubar",
            targets: ["RemoteWisprMenuBar"]
        ),
        .executable(
            name: "remote-wispr-input-spike",
            targets: ["RemoteWisprInputAutomationSpike"]
        )
    ],
    targets: [
        .target(
            name: "RemoteWisprCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "RemoteWisprSpike",
            dependencies: ["RemoteWisprCore"]
        ),
        .executableTarget(
            name: "RemoteWisprFixtureTests",
            dependencies: ["RemoteWisprCore"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "RemoteWisprDonorApp",
            dependencies: ["RemoteWisprCore"]
        ),
        .executableTarget(
            name: "RemoteWisprMenuBar",
            dependencies: ["RemoteWisprCore"]
        ),
        .executableTarget(
            name: "RemoteWisprInputAutomationSpike",
            dependencies: ["RemoteWisprCore"]
        )
    ]
)

// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RelatoKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "RelatoKit", targets: ["RelatoKit"]),
        .executable(name: "relato", targets: ["relato"])
    ],
    targets: [
        .target(
            name: "RelatoKit",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "relato",
            dependencies: ["RelatoKit"]
        ),
        .testTarget(
            name: "RelatoKitTests",
            dependencies: ["RelatoKit"]
        )
    ]
)

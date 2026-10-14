// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TranskriptHub",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "TranskriptHubCore",
            targets: ["TranskriptHubCore"]
        ),
        .executable(
            name: "TranskriptHubApp",
            targets: ["TranskriptHubApp"]
        ),
        .executable(
            name: "transkripthub-cli",
            targets: ["transkripthub-cli"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .binaryTarget(
            name: "whisper",
            path: "Frameworks/whisper.xcframework"
        ),
        .target(
            name: "TranskriptHubCore",
            dependencies: [
                "whisper",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "TranskriptHubApp",
            dependencies: [
                "TranskriptHubCore"
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "transkripthub-cli",
            dependencies: [
                "TranskriptHubCore"
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "TranskriptHubCoreTests",
            dependencies: ["TranskriptHubCore"]
        )
    ]
)

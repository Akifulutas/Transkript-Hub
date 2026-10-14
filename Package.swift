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
            name: "transkripthub-cli",
            targets: ["transkripthub-cli"]
        ),
    ],
    dependencies: [],
    targets: [
        .binaryTarget(
            name: "whisper",
            path: "Frameworks/whisper.xcframework"
        ),
        .target(
            name: "TranskriptHubCore",
            dependencies: [
                "whisper"
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

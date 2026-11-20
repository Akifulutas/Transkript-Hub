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
            name: "CQwenASR",
            path: "Sources/CQwenASR",
            publicHeadersPath: "include",
            cSettings: [
                .define("USE_BLAS"),
                .define("ACCELERATE_NEW_LAPACK"),
                .unsafeFlags(["-O3", "-ffast-math", "-mcpu=apple-m1", "-funroll-loops"])
            ],
            linkerSettings: [
                .linkedFramework("Accelerate")
            ]
        ),
        .target(
            name: "TranskriptHubCore",
            dependencies: [
                "whisper",
                "CQwenASR",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release))
            ]
        ),
        .executableTarget(
            name: "TranskriptHubApp",
            dependencies: [
                "TranskriptHubCore"
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release))
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-dead_strip"], .when(configuration: .release))
            ]
        ),
        .executableTarget(
            name: "transkripthub-cli",
            dependencies: [
                "TranskriptHubCore"
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release))
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-dead_strip"], .when(configuration: .release))
            ]
        ),
        .testTarget(
            name: "TranskriptHubCoreTests",
            dependencies: ["TranskriptHubCore"]
        )
    ]
)

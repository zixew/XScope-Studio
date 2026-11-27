// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DevCompanionMac",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DevCompanionMac", targets: ["DevCompanionMac"]),
        .library(name: "DevCompanionCore", targets: ["DevCompanionCore"])
    ],
    targets: [
        .target(
            name: "DevCompanionCore",
            dependencies: []
        ),
        .executableTarget(
            name: "DevCompanionMac",
            dependencies: ["DevCompanionCore"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "DevCompanionCoreTests",
            dependencies: ["DevCompanionCore"]
        )
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DevCompanionKit",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(name: "DevCompanionKit", targets: ["DevCompanionKit"])
    ],
    targets: [
        .target(name: "DevCompanionKit")
    ]
)

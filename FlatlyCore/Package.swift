// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlatlyCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FlatlyCore", targets: ["FlatlyCore"])
    ],
    targets: [
        .target(
            name: "FlatlyCore",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "FlatlyCoreTests",
            dependencies: ["FlatlyCore"]
        )
    ],
    swiftLanguageModes: [.v6]
)

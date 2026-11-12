// swift-tools-version: 6.0
// Renders the synthetic photo fixtures in TestFixtures. Run via scripts/generate-fixtures.sh.
import PackageDescription

let package = Package(
    name: "FixtureGenerator",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "FixtureGenerator")
    ]
)

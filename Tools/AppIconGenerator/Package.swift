// swift-tools-version: 6.0
// Renders the Offscan app icon with CoreGraphics. Run via scripts/generate-icon.sh.
import PackageDescription

let package = Package(
    name: "AppIconGenerator",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "AppIconGenerator")
    ]
)

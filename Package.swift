// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GlasshouseTray",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GlasshouseTray",
            path: "Sources/GlasshouseTray"
        ),
    ]
)

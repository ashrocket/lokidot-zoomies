// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LokiDotZoomies",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "LokiDotZoomies", targets: ["LokiDotZoomies"]),
        .executable(name: "lokidot", targets: ["LokiDotCLI"]),
        .executable(name: "SpritePackTool", targets: ["SpritePackTool"])
    ],
    targets: [
        .target(name: "ZoomiesCore"),
        .executableTarget(name: "LokiDotZoomies", dependencies: ["ZoomiesCore"]),
        .executableTarget(name: "LokiDotCLI", dependencies: ["ZoomiesCore"]),
        .executableTarget(name: "SpritePackTool", dependencies: ["ZoomiesCore"]),
        .testTarget(name: "ZoomiesCoreTests", dependencies: ["ZoomiesCore"])
    ]
)

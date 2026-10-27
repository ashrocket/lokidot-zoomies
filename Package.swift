// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LokiDotZoomies",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "LokiDotZoomies", targets: ["LokiDotZoomies"])],
    targets: [
        .target(name: "ZoomiesCore"),
        .executableTarget(name: "LokiDotZoomies", dependencies: ["ZoomiesCore"]),
        .testTarget(name: "ZoomiesCoreTests", dependencies: ["ZoomiesCore"])
    ]
)

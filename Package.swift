// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MoreCorners",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "MoreCornersCore",
            path: "Sources/MoreCornersCore"
        ),
        .executableTarget(
            name: "MoreCorners",
            dependencies: ["MoreCornersCore"],
            path: "Sources/MoreCorners"
        ),
        .testTarget(
            name: "MoreCornersCoreTests",
            dependencies: ["MoreCornersCore"],
            path: "Tests/MoreCornersCoreTests"
        ),
    ]
)

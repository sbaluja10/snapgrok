// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "snapgrok",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Snapgrok", targets: ["Snapgrok"])
    ],
    targets: [
        .target(name: "SnapgrokCore"),
        .executableTarget(
            name: "Snapgrok",
            dependencies: ["SnapgrokCore"]
        ),
        .testTarget(
            name: "SnapgrokTests",
            dependencies: ["SnapgrokCore"]
        ),
    ]
)

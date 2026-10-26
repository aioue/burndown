// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Burndown",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Burndown", targets: ["Burndown"]),
    ],
    targets: [
        .target(name: "BurndownCore"),
        .executableTarget(name: "Burndown", dependencies: ["BurndownCore"]),
        .testTarget(name: "BurndownCoreTests", dependencies: ["BurndownCore"]),
    ]
)

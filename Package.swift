// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Expire",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Expire", targets: ["Expire"]),
    ],
    targets: [
        .target(name: "ExpireCore"),
        .executableTarget(name: "Expire", dependencies: ["ExpireCore"]),
        .testTarget(name: "ExpireCoreTests", dependencies: ["ExpireCore"]),
    ]
)

// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "RoostPlayground",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RoostPlayground", targets: ["RoostPlayground"]),
        .executable(name: "roost-playground", targets: ["PlaygroundCLI"]),
    ],
    dependencies: [
        .package(path: "../esw"),
        .package(path: "../Peregrine"),
        .package(path: "../Nexus"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
    ],
    targets: [
        .target(name: "RoostPlayground", dependencies: [
            "PlaygroundTheme",
            .product(name: "ESWLive", package: "esw"),
            .product(name: "Roost", package: "peregrine"),
            .product(name: "Nexus", package: "nexus"),
        ]),
        .target(name: "PlaygroundTheme", resources: [.copy("Resources")]),
        .target(name: "PlaygroundCore"),
        .executableTarget(name: "PlaygroundCLI", dependencies: [
            "PlaygroundCore", "PlaygroundTheme", .product(name: "Hummingbird", package: "hummingbird"),
        ], resources: [.copy("Resources")]),
        .testTarget(name: "PlaygroundCoreTests", dependencies: ["PlaygroundCore"]),
        .testTarget(name: "RoostPlaygroundTests", dependencies: [
            "RoostPlayground", .product(name: "RoostTest", package: "peregrine"),
        ]),
    ],
    swiftLanguageModes: [.v6]
)

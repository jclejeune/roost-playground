// swift-tools-version: 6.3
import Foundation
import PackageDescription

// Set ROOST_ECOSYSTEM_PATH to a folder containing esw/, Nexus/, Peregrine/, and Spectro/
// to develop them together. Roost reads the same variable, so all packages agree on one copy.
let ecosystem = ProcessInfo.processInfo.environment["ROOST_ECOSYSTEM_PATH"]
func dependency(_ name: String, folder: String, url: String, from version: Version,
                traits: Set<Package.Dependency.Trait> = [.defaults]) -> Package.Dependency {
    if let ecosystem { return .package(name: name, path: "\(ecosystem)/\(folder)", traits: traits) }
    return .package(url: url, from: version, traits: traits)
}

let package = Package(
    name: "RoostPlayground",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RoostPlayground", targets: ["RoostPlayground"]),
        .executable(name: "roost-playground", targets: ["PlaygroundCLI"]),
    ],
    dependencies: [
        dependency("esw", folder: "esw", url: "https://github.com/roost-framework/ESW.git", from: "1.6.0"),
        dependency("swift-roost", folder: "Peregrine", url: "https://github.com/roost-framework/swift-roost.git", from: "2.1.2"),
        // The playground doesn't use Nexus's Vapor adapter; neither does Roost.
        dependency("nexus", folder: "Nexus", url: "https://github.com/roost-framework/Nexus.git", from: "2.1.0", traits: []),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
    ],
    targets: [
        .target(name: "RoostPlayground", dependencies: [
            "PlaygroundTheme",
            .product(name: "ESWLive", package: "esw"),
            .product(name: "Roost", package: "swift-roost"),
            .product(name: "Nexus", package: "nexus"),
        ]),
        .target(name: "PlaygroundTheme", resources: [.copy("Resources")]),
        .target(name: "PlaygroundCore"),
        .executableTarget(name: "PlaygroundCLI", dependencies: [
            "PlaygroundCore", "PlaygroundTheme", .product(name: "Hummingbird", package: "hummingbird"),
        ], resources: [.copy("Resources")]),
        .testTarget(name: "PlaygroundCoreTests", dependencies: ["PlaygroundCore"]),
        .testTarget(name: "RoostPlaygroundTests", dependencies: [
            "RoostPlayground", .product(name: "RoostTest", package: "swift-roost"),
        ]),
    ],
    swiftLanguageModes: [.v6]
)

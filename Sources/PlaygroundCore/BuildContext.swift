import CryptoKit
import Foundation

/// Additional inputs to a preview build. This cache never crosses runner/toolchain sessions.
struct BuildContext {
    let inputsHash: String
    private let resolutionHash: String
    var fingerprint: String { digest(inputsHash + resolutionHash) }

    static func capture(configuration: Configuration, workspace: Workspace) throws -> Self {
        let manager = FileManager.default
        let parent = configuration.packageRoot.deletingLastPathComponent()
        // These are the local dependencies of the generated package and RoostPlayground.
        let packages = [configuration.packageRoot] + ["esw", "Peregrine", "Nexus"].map { parent.appending(path: $0) }
        var hasher = SHA256()
        for package in packages {
            for name in ["Package.swift", "Package.resolved"] {
                let file = package.appending(path: name)
                try append(file, to: &hasher)
            }
            for name in ["Sources", "Plugins"] {
                let root = package.appending(path: name)
                guard manager.fileExists(atPath: root.path) else { continue }
                guard let enumerator = manager.enumerator(atPath: root.path) else {
                    throw PlaygroundError("Cannot read package inputs at \(root.path)")
                }
                let paths = enumerator.compactMap { $0 as? String }.sorted()
                for path in paths where !path.split(separator: "/").contains(where: { $0.hasPrefix(".") }) {
                    let file = root.appending(path: path)
                    let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    if values.isRegularFile == true { try append(file, to: &hasher) }
                }
            }
        }
        var resolution = SHA256()
        try append(workspace.root.appending(path: "Package.resolved"), to: &resolution)
        return Self(inputsHash: hex(hasher.finalize()), resolutionHash: hex(resolution.finalize()))
    }

    private static func append(_ file: URL, to hasher: inout SHA256) throws {
        hasher.update(data: Data("\(file.path.utf8.count):\(file.path)".utf8))
        guard FileManager.default.fileExists(atPath: file.path) else {
            hasher.update(data: Data("missing:".utf8))
            return
        }
        let data = try Data(contentsOf: file)
        hasher.update(data: Data("\(data.count):".utf8))
        hasher.update(data: data)
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

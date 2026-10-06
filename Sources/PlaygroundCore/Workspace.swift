import Darwin
import Foundation

public final class WorkspaceLock {
    private var descriptor: Int32

    /// Nil when another process holds the lock.
    fileprivate init?(url: URL) throws {
        let acquired = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard acquired >= 0 else { throw PlaygroundError("Cannot open workspace lock: \(url.path)") }
        guard flock(acquired, LOCK_EX | LOCK_NB) == 0 else {
            close(acquired)
            return nil
        }
        // Only take ownership after success. A fully initialized class runs deinit even when
        // init throws; closing in both paths could close an unrelated descriptor reused by another thread.
        descriptor = acquired
    }

    /// Releases early, for a lock held across part of a function.
    public func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }

    deinit { release() }
}

/// The release tag an installed binary compiles previews against. Bump it with each tag.
let playgroundVersion = "1.0.0"

public struct Workspace: Sendable {
    public let configuration: Configuration
    /// Per input: its lock, logs, staged runs, and saved versions.
    public let root: URL
    /// Every input builds in one generated package, so dependencies compile once per installation.
    public let package: URL
    public var scratch: URL { package.appending(path: ".build") }
    public var logs: URL { root.appending(path: "logs") }

    public init(configuration: Configuration) {
        self.configuration = configuration
        let previews = configuration.cacheRoot.appending(path: "previews")
        root = previews.appending(path: String(digest(configuration.source.path).prefix(24)))
        package = previews.appending(path: "package")
    }

    public func acquire() throws -> WorkspaceLock {
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        guard let lock = try WorkspaceLock(url: root.appending(path: "playground.lock")) else {
            throw PlaygroundError("This file already has a running playground. Stop it before starting another.")
        }
        // Earlier versions generated a package per input; its build products are now unused.
        for legacy in [".build", "Sources", "Package.swift", "Package.resolved"] {
            try? manager.removeItem(at: root.appending(path: legacy))
        }
        return lock
    }

    /// Hold the result from writing the shared package until its products are staged.
    /// Runners for other inputs wait here while this one builds.
    public func lockPackage() async throws -> WorkspaceLock {
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        while true {
            if let lock = try WorkspaceLock(url: package.appending(path: "build.lock")) { return lock }
            try await Task.sleep(for: .milliseconds(200))
        }
    }

    public func prepare(snapshot: SourceSnapshot) throws {
        let manager = FileManager.default
        let target = package.appending(path: "Sources/PlaygroundPage")
        let views = target.appending(path: "Views")
        try manager.createDirectory(at: target, withIntermediateDirectories: true)
        try manager.createDirectory(at: logs, withIntermediateDirectories: true)
        // A checkout compiles previews against its own sources; an installed binary fetches its release.
        let library = FileManager.default.fileExists(atPath: configuration.packageRoot.appending(path: "Package.swift").path)
            ? ".package(name: \"roost-playground\", path: \(String(reflecting: configuration.packageRoot.path)))"
            : ".package(url: \"https://github.com/roost-framework/roost-playground.git\", exact: \"\(playgroundVersion)\")"
        let esw = configuration.ecosystemRoot.map { ".package(path: \(String(reflecting: $0.appending(path: "esw").path)))" }
            ?? ".package(url: \"https://github.com/roost-framework/ESW.git\", from: \"1.5.0\")"
        let manifest = """
        // swift-tools-version: 6.3
        import PackageDescription
        let package = Package(
            name: "PlaygroundPage",
            platforms: [.macOS(.v14)],
            products: [.executable(name: "PlaygroundPage", targets: ["PlaygroundPage"])],
            dependencies: [
                \(library),
                \(esw)
            ],
            targets: [
                .executableTarget(
                    name: "PlaygroundPage",
                    dependencies: [.product(name: "RoostPlayground", package: "roost-playground")],
                    plugins: [.plugin(name: "ESWBuildPlugin", package: "esw")]
                )
            ],
            swiftLanguageModes: [.v6]
        )
        """
        try writeIfChanged(manifest + "\n", to: package.appending(path: "Package.swift"))
        let mapped = "#sourceLocation(file: \(String(reflecting: configuration.source.path)), line: 1)\n" + snapshot.source
        try writeIfChanged(mapped, to: target.appending(path: "Page.swift"))
        if let files = manager.enumerator(atPath: views.path) {
            for case let relative as String in files {
                let file = views.appending(path: relative)
                guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
                if snapshot.templates[relative] == nil { try manager.removeItem(at: file) }
            }
        }
        for (path, contents) in snapshot.templates {
            let destination = views.appending(path: path)
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try writeIfChanged(contents, to: destination)
        }
    }

    public func mapDiagnostics(_ text: String) -> String {
        // Swift diagnostics may retain the escapes from #sourceLocation's file literal.
        let escapedSource = String(String(reflecting: configuration.source.path).dropFirst().dropLast())
        return text.replacingOccurrences(of: escapedSource, with: configuration.source.path)
            .replacingOccurrences(of: package.appending(path: "Sources/PlaygroundPage/Views").path, with: configuration.views.path)
            .replacingOccurrences(of: package.appending(path: "Sources/PlaygroundPage/Page.swift").path, with: configuration.source.path)
    }

    /// An active preview must never depend on build products that a later compilation can replace.
    public func stage(binaryDirectory: URL) throws -> URL {
        let manager = FileManager.default
        let run = root.appending(path: "runs/\(UUID().uuidString)")
        try manager.createDirectory(at: run, withIntermediateDirectories: true)
        do {
            for file in try manager.contentsOfDirectory(at: binaryDirectory, includingPropertiesForKeys: nil)
                where file.lastPathComponent == "PlaygroundPage" || ["bundle", "dylib"].contains(file.pathExtension) {
                try manager.copyItem(at: file, to: run.appending(path: file.lastPathComponent))
            }
            let executable = run.appending(path: "PlaygroundPage")
            guard manager.isExecutableFile(atPath: executable.path) else {
                throw PlaygroundError("Swift built no PlaygroundPage executable in \(binaryDirectory.path)")
            }
            return executable
        } catch {
            try? manager.removeItem(at: run)
            throw error
        }
    }
}

private func writeIfChanged(_ content: String, to url: URL) throws {
    guard (try? String(contentsOf: url, encoding: .utf8)) != content else { return }
    try content.write(to: url, atomically: true, encoding: .utf8)
}

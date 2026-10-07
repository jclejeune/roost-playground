import Foundation
import Hummingbird
import PlaygroundCore
import PlaygroundTheme

@main
struct Command {
    @MainActor static func main() async {
        do { try await run() }
        catch {
            FileHandle.standardError.write(Data("playground: \(error)\n".utf8))
            exit(1)
        }
    }

    @MainActor private static func run() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("--help") || arguments.contains("-h") {
            print("""
            Roost Playground
            Usage: playground <file.swift> [--port 4567] [--no-open]
                   playground new <file.swift> [--port 4567] [--no-open]
                   playground clean

            `new` writes a starter playground to the file, then runs it.
            `clean` removes build caches that no running playground uses.

            Save the Swift file or a template in its sibling Views directory to rebuild.
            Failed builds keep the last working preview. Successful reloads reset live state.
            Press Ctrl-C to stop the playground and its preview processes.
            """)
            return
        }
        if arguments == ["clean"] {
            let result = Caches.clean()
            let bytes = result.removed.reduce(0) { $0 + $1.bytes }
            print("Removed \(result.removed.count) cache\(result.removed.count == 1 ? "" : "s") from \(Caches.base.path), "
                + "freeing \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)).")
            for root in result.inUse { print("Kept \(root.path): a playground is running from it.") }
            return
        }
        let environment = ProcessInfo.processInfo.environment
        let packageRoot = environment["ROOST_PLAYGROUND_ROOT"].map { URL(filePath: $0) }
            ?? URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let configuration = try Configuration(arguments: arguments,
                                              currentDirectory: URL(filePath: FileManager.default.currentDirectoryPath),
                                              packageRoot: packageRoot,
                                              cacheRoot: environment["ROOST_PLAYGROUND_CACHE"].map { URL(filePath: $0) },
                                              ecosystemRoot: environment["ROOST_ECOSYSTEM_PATH"].map { URL(filePath: $0) })
        if configuration.createsSource {
            try Data(starterPlayground.utf8).write(to: configuration.source, options: .withoutOverwriting)
            print("Created \(configuration.source.path)")
        }
        let supervisor = try Supervisor(configuration: configuration)
        Task.detached(priority: .background) {
            for root in Caches.prune(keeping: configuration.cacheRoot) { print("Removed unused cache \(root.path)") }
        }
        let router = Router()
        var assets = [
            (path: "/roost.css", type: "text/css; charset=utf-8", body: Data(PlaygroundTheme.stylesheet.utf8)),
            (path: "/roost.png", type: "image/png", body: PlaygroundTheme.logo),
        ]
        for (path, name, type) in [("/", "index.html", "text/html; charset=utf-8"),
                                    ("/playground.js", "playground.js", "text/javascript; charset=utf-8"),
                                    ("/playground.css", "playground.css", "text/css; charset=utf-8")] {
            guard let file = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Resources") else {
                throw PlaygroundError("Missing playground resource: \(name)")
            }
            assets.append((path: path, type: type, body: try Data(contentsOf: file)))
        }
        for asset in assets {
            router.get(RouterPath(asset.path)) { request, _ in
                try checkHost(request, port: configuration.port)
                return Response(status: .ok, headers: [.contentType: asset.type, .cacheControl: "no-store"],
                                body: .init(byteBuffer: .init(bytes: asset.body)))
            }
        }
        router.get("/__playground/status") { request, _ in
            try checkHost(request, port: configuration.port)
            let data = try await JSONEncoder().encode(supervisor.status)
            return Response(status: .ok, headers: [.contentType: "application/json", .cacheControl: "no-store"],
                            body: .init(byteBuffer: .init(bytes: data)))
        }
        let app = Application(router: router,
                              configuration: .init(address: .hostname("127.0.0.1", port: configuration.port)),
                              onServerRunning: { _ in
            print("Roost Playground → \(configuration.address)\nWatching \(configuration.source.path)")
            if configuration.opensBrowser {
                let opener = Process()
                opener.executableURL = URL(filePath: "/usr/bin/open")
                opener.arguments = [configuration.address]
                try? opener.run()
            }
        })
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { await supervisor.run() }
                group.addTask { try await app.runService() }
                defer { group.cancelAll() }
                try await group.next()
            }
        } catch {
            await supervisor.shutdown()
            throw error
        }
    }

    private static func checkHost(_ request: Request, port: Int) throws {
        guard let host = request.head.authority,
              ["127.0.0.1:\(port)", "localhost:\(port)"].contains(host.lowercased()) else {
            throw HTTPError(.forbidden)
        }
    }
}

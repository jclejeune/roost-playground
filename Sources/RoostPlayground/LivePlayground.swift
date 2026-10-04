@_exported import ESWLive
@_exported import Roost
import Foundation
import Nexus
import PlaygroundTheme

/// A regular ESW live view with a standalone development entry point.
/// Add `@main` to your conforming type and run `playground YourFile.swift`.
public protocol LivePlayground: LiveView {
    init()
    static var title: String { get }
    static func main() async throws
}

extension LivePlayground {
    public static var title: String { "Roost Playground" }

    public static func main() async throws {
        try await PlaygroundApplication<Self>.main()
    }
}

private struct PlaygroundApplication<Page: LivePlayground>: RoostApp {
    private let live = PlaygroundLivePage(Page())
    private let store = MemorySessionStore()

    var plugs: [Plug] {
        let identity = ProcessInfo.processInfo.environment["ROOST_PLAYGROUND_ID"] ?? String(server.port)
        return [session(store: store, cookieName: "_roost_playground_" + identity)] + browserPlugs()
    }
    var server: ServerConfig {
        // A playground always listens on loopback, including when the surrounding shell has a production host set.
        .init(host: "127.0.0.1", port: ProcessInfo.processInfo.environment["ROOST_PORT"].flatMap(Int.init) ?? 8080)
    }

    var routes: [Route] {
        GET("/") { conn in try await live.render(conn, layout: Self.layout) }
        live.routes
        GET("/__playground/health") { conn in
            try conn.json(value: ["token": ProcessInfo.processInfo.environment["ROOST_PLAYGROUND_TOKEN"] ?? ""])
                .putRespHeader(.cacheControl, "no-store")
        }
    }

    private static func layout(_ html: String) -> String {
        """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(ESW.escape(Page.title))</title>
        <style>
        \(PlaygroundTheme.stylesheet)
        </style></head><body>\(html)</body></html>
        """
    }
}

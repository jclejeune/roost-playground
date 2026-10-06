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
    private let preserved: PreservedState<Page.State>
    private let live: PlaygroundLivePage<PreservingView<Page>>
    private let store = MemorySessionStore()
    private let token = ProcessInfo.processInfo.environment["ROOST_PLAYGROUND_TOKEN"] ?? ""

    init() {
        preserved = PreservedState(seed: Self.carriedState())
        live = PlaygroundLivePage(PreservingView(page: Page(), preserved: preserved))
    }

    /// The supervisor hands over the previous process's state in a file.
    private static func carriedState() -> Page.State? {
        guard let path = ProcessInfo.processInfo.environment["ROOST_PLAYGROUND_STATE"],
              let data = FileManager.default.contents(atPath: path) else { return nil }
        guard let state = PreservedState<Page.State>.decode(data) else {
            print("The live state no longer matches \(Page.State.self); starting fresh.")
            return nil
        }
        return state
    }

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
            try conn.json(value: ["token": token]).putRespHeader(.cacheControl, "no-store")
        }
        GET("/__playground/state") { conn in
            // Only the supervisor knows this process's token.
            guard !token.isEmpty, conn.getReqHeader("X-Playground-Token") == token,
                  let data = preserved.encodedLatest() else { return conn.respond(status: .noContent, body: .empty) }
            return conn.respond(status: .ok, body: .buffered(data))
                .putRespHeader(.contentType, "application/json")
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

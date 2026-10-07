@_exported import ESWLive
@_exported import Roost
import Foundation
import Nexus
import PlaygroundTheme

/// A regular ESW live view with a standalone development entry point.
/// Add `@main` to your conforming type and run `playground YourFile.swift`.
public protocol LivePlayground: Interactive {
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
        let context = PlaygroundContext(live: live, preserved: preserved, token: token)
        return [session(store: store, cookieName: "_roost_playground_" + identity)] + browserPlugs() + [
            { conn in conn.assign(PlaygroundContextKey<Page>.self, value: context) },
        ]
    }
    var server: ServerConfig {
        // A playground always listens on loopback, including when the surrounding shell has a production host set.
        .init(host: "127.0.0.1", port: ProcessInfo.processInfo.environment["ROOST_PORT"].flatMap(Int.init) ?? 8080)
    }

    var routes: [Route] {
        GET("/", PlaygroundController<Page>.self, .page)
        live.routes
        GET("/__playground/health", PlaygroundController<Page>.self, .health)
        GET("/__playground/state", PlaygroundController<Page>.self, .state)
    }
}

/// What the playground's own actions need from the running application.
private struct PlaygroundContext<Page: LivePlayground>: Sendable {
    let live: PlaygroundLivePage<PreservingView<Page>>
    let preserved: PreservedState<Page.State>
    let token: String
}

private enum PlaygroundContextKey<Page: LivePlayground>: AssignKey {
    typealias Value = PlaygroundContext<Page>
}

/// The playground page and the supervisor's health and state checks.
private struct PlaygroundController<Page: LivePlayground>: Controller {
    enum Action: String, ControllerAction {
        case page, health, state
    }

    static func action(_ action: Action) -> Plug {
        switch action {
        case .page: page
        case .health: health
        case .state: state
        }
    }

    static func page(_ conn: Connection) async throws -> Connection {
        try await context(conn).live.render(conn, layout: layout)
    }

    static func health(_ conn: Connection) async throws -> Connection {
        try conn.json(value: ["token": context(conn).token]).putRespHeader(.cacheControl, "no-store")
    }

    static func state(_ conn: Connection) async throws -> Connection {
        let context = try context(conn)
        // Only the supervisor knows this process's token.
        guard !context.token.isEmpty, conn.getReqHeader("X-Playground-Token") == context.token,
              let data = context.preserved.encodedLatest() else { return conn.respond(status: .noContent, body: .empty) }
        return conn.respond(status: .ok, body: .buffered(data))
            .putRespHeader(.contentType, "application/json")
            .putRespHeader(.cacheControl, "no-store")
    }

    private static func context(_ conn: Connection) throws -> PlaygroundContext<Page> {
        guard let context = conn[PlaygroundContextKey<Page>.self] else {
            throw NexusHTTPError(.internalServerError, message: "The playground context is missing")
        }
        return context
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

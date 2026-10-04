@_exported import ESWLive
@_exported import Roost
import Foundation
import Nexus

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
        :root{font-family:system-ui,sans-serif;color:#1b302a;background:#fafcf9;color-scheme:light}
        body{margin:0}main{max-width:720px;margin:64px auto;padding:0 28px 64px}
        h1{font-size:clamp(32px,6vw,52px);line-height:1.1;letter-spacing:-.045em}h2{font-size:18px}
        p{line-height:1.6}section{border-top:1px solid #dbe3da;padding:24px 0;margin-top:32px}
        button,input{font:inherit;border:1px solid #b9cbbf;border-radius:7px;padding:10px 15px}
        button{cursor:pointer;background:#e9f0e8;color:inherit}button:hover{background:#dce8db}
        input{background:white;color:inherit;min-width:0}button:focus-visible,input:focus-visible{outline:3px solid #5d8872;outline-offset:3px}
        label{display:block;margin-bottom:10px}.counter{display:flex;align-items:center;gap:28px}
        output{font-size:48px;font-variant-numeric:tabular-nums;min-width:70px;text-align:center}
        .form-row{display:flex;gap:12px}.form-row input{flex:1}.muted{color:#5d7366}
        [data-esw-state=disconnected],[data-esw-state=expired]{opacity:.65}
        @media(max-width:500px){main{margin-top:36px}.form-row{flex-direction:column}}
        </style></head><body>\(html)</body></html>
        """
    }
}

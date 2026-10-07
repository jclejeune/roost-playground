@testable import RoostPlayground
import RoostTest
import Testing

private struct RouteCounter: Interactive {
    func mount(_ context: LiveContext) async throws -> Int { context.isConnected ? 10 : 0 }
    func handleEvent(_ event: LiveEvent, state: Int) async throws -> Int {
        guard event.name == "increment" else { throw LiveError.invalidEvent }
        return state + 1
    }
    func render(_ state: Int) -> ESWLiveRender { #live("<p>{state}</p>") }
}

private struct RouteApp: RoostApp {
    let live = PlaygroundLivePage(RouteCounter(), authorize: { conn in
        if conn.getReqHeader("X-Deny") == "yes" { throw LiveError.unauthorized }
    })
    let store = MemorySessionStore()
    var sessionStore: SessionStore? { store }
    // Deliberately omit browserPlugs: the live adapter must enforce CSRF itself.
    @RouteBuilder var routes: [Route] {
        scope("/", plugs: [live.assignment]) {
            GET("/", RouteController.self, .page)
            // The in-process helper cannot consume writer-based SSE responses.
            // Connect the state here; BrowserTests exercises the real SSE socket.
            GET("/connect/:id", RouteController.self, .connect)
            POST("/invalidate", RouteController.self, .invalidate)
        }
        live.routes
    }
}

private struct RouteController: Controller {
    enum Action: String, ControllerAction { case page, connect, invalidate }

    static func action(_ action: Action) -> Plug {
        switch action {
        case .page: page
        case .connect: connect
        case .invalidate: invalidate
        }
    }

    static func page(_ conn: Connection) async throws -> Connection {
        try await PlaygroundLivePage<RouteCounter>.current(conn).render(conn)
    }

    static func connect(_ conn: Connection) async throws -> Connection {
        let live = try PlaygroundLivePage<RouteCounter>.current(conn)
        guard let owner = conn.getSession(PlaygroundLivePage<RouteCounter>.ownerKey) else { throw LiveError.unauthorized }
        var updates = try await live.host.subscribe(conn.params["id"] ?? "", owner: owner).makeAsyncIterator()
        return try conn.json(value: await updates.next())
    }

    static func invalidate(_ conn: Connection) async throws -> Connection {
        let live = try PlaygroundLivePage<RouteCounter>.current(conn)
        await live.invalidate(conn)
        return conn.respond(status: .noContent, body: .empty)
    }
}

@Test func liveRoutesEnforceSessionsCSRFValidationAndRevocation() async throws {
    let app = try await TestApp(RouteApp.self)
    let browser = app.browser(), outsider = app.browser()
    let page = try await browser.get("/")
    #expect(page.status == .ok)
    #expect(page.text.contains("<p>0</p>"))
    #expect(page.header("Cache-Control") == "private, no-store")
    func attribute(_ name: String) throws -> String {
        let suffix = try #require(page.text.components(separatedBy: "\(name)=\"").dropFirst().first)
        return String(try #require(suffix.split(separator: "\"").first))
    }
    let stream = try attribute("data-esw-stream")
    let id = try attribute("data-esw-id")
    let endpoint = try attribute("data-esw-event")
    let headers = ["Content-Type": "application/json", "X-CSRF-Token": try attribute("data-esw-csrf")]
    let event = LiveEvent(id: "first", name: "increment", baseRevision: 1)
    let body = try JSONEncoder().encode(event)

    #expect(try await outsider.get(stream).status == .forbidden)
    #expect(try await browser.get(stream, headers: ["Sec-Fetch-Site": "cross-site"]).status == .forbidden)
    #expect(try await browser.get(stream, headers: ["X-Deny": "yes"]).status == .forbidden)
    let connected = try await browser.get("/connect/\(id)")
    #expect(connected.status == .ok)
    #expect(try connected.decode(as: LiveUpdate.self).revision == 1)

    #expect(try await browser.request(method: .post, path: endpoint, body: body).status == .forbidden)
    #expect(try await outsider.request(method: .post, path: endpoint, body: body, headers: headers).status == .forbidden)
    var denied = headers
    denied["X-Deny"] = "yes"
    #expect(try await browser.request(method: .post, path: endpoint, body: body, headers: denied).status == .forbidden)
    var badToken = headers
    badToken["X-CSRF-Token"] = "wrong"
    #expect(try await browser.request(method: .post, path: endpoint, body: body, headers: badToken).status == .forbidden)
    for invalid in [Data("{".utf8), try JSONEncoder().encode(LiveEvent(name: "increment")), Data(repeating: 32, count: 65_537)] {
        #expect(try await browser.request(method: .post, path: endpoint, body: invalid, headers: headers).status == .unprocessableContent)
    }
    let response = try await browser.request(method: .post, path: endpoint, body: body, headers: headers)
    #expect(response.status == .ok)
    let update = try response.decode(as: LiveUpdate.self)
    #expect(update.revision == 2)
    #expect(update.render.dynamics == ["0": "11"])
    let retry = try await browser.request(method: .post, path: endpoint, body: body, headers: headers)
    #expect(try retry.decode(as: LiveUpdate.self) == update)
    let stale = try JSONEncoder().encode(LiveEvent(name: "increment", baseRevision: 1))
    #expect(try await browser.request(method: .post, path: endpoint, body: stale, headers: headers).status == .conflict)
    let invalidEvent = try JSONEncoder().encode(LiveEvent(name: "unknown", baseRevision: 2))
    #expect(try await browser.request(method: .post, path: endpoint, body: invalidEvent, headers: headers).status == .unprocessableContent)
    #expect(try await browser.request(method: .post, path: "/invalidate", headers: headers).status == .noContent)
    #expect(try await browser.get(stream).status == .noContent)
    #expect(try await browser.request(method: .post, path: endpoint, body: body, headers: headers).status == .notFound)
}

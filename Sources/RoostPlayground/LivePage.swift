// Adapted from ESWLivePeregrine for the renamed Roost framework.
// Kept private to the playground while the upstream integration migrates.
import ESWLive
import Roost
import Nexus

/// A live route uses the application's server-side session middleware.
/// `authorize` runs on the initial page and every stream/event request.
struct PlaygroundLivePage<View: Interactive>: Sendable {
    let host: LiveHost<View>
    let path: String
    private let authorize: @Sendable (Connection) async throws -> Void
    static var ownerKey: String { "_esw_live_owner" }

    init(_ view: View, path: String = "/_live", capacity: Int = 1_000,
                lifetime: Duration = .seconds(3_600),
                authorize: @escaping @Sendable (Connection) async throws -> Void = { _ in }) {
        precondition(path.hasPrefix("/") && !path.hasSuffix("/") && !path.contains("?") && !path.contains("#"))
        self.host = LiveHost(view, capacity: capacity, lifetime: lifetime)
        self.path = path
        self.authorize = authorize
    }

    func render(_ connection: Connection, context: LiveContext = .init(),
                       layout: @Sendable (String) -> String = { $0 }) async throws -> Connection {
        try await authorize(connection)
        guard connection[RoostSessionKey.self] != nil else { throw LiveError.unauthorized }
        var conn = connection
        if conn.getSession(Self.ownerKey) == nil {
            conn = conn.putSession(key: Self.ownerKey, value: Auth.generateToken())
        }
        let (csrf, protected) = csrfToken(conn: conn)
        conn = protected
        let owner = try owner(conn)
        let mount = try await host.mount(owner: owner, context: context)
        let root = "esw-live-" + mount.id
        let fragment = """
        <div id="\(ESW.escape(root))" data-esw-live data-esw-id="\(ESW.escape(mount.id))" data-esw-state="connecting" data-esw-stream="\(ESW.escape(path))/\(mount.id)/stream" data-esw-event="\(ESW.escape(path))/\(mount.id)/event" data-esw-csrf="\(ESW.escape(csrf))">\(mount.render.html)</div>
        <script type="module" src="\(ESW.escape(path))/assets/esw-live.js"></script>
        """
        return conn.html(layout(fragment)).putRespHeader(.cacheControl, "private, no-store")
    }

    /// The page's asset, stream, and event routes, served by ``LiveController``.
    @RouteBuilder var routes: [Route] {
        scope(path, plugs: [assignment]) {
            GET("/assets/:name", LiveController<View>.self, .asset)
            GET("/:id/stream", LiveController<View>.self, .stream)
            POST("/:id/event", LiveController<View>.self, .event)
        }
    }

    /// Puts this page in the request for the controller actions that serve it.
    var assignment: Plug {
        { conn in conn.assign(LivePageKey<View>.self, value: self) }
    }

    /// The page a request was routed through by ``assignment``.
    static func current(_ conn: Connection) throws -> Self {
        guard let page = conn[LivePageKey<View>.self] else { throw LiveError.notFound }
        return page
    }

    func asset(_ conn: Connection) -> Connection {
        guard let name = conn.params["name"], let source = LiveAssets.javascript(named: name) else {
            return conn.respond(status: .notFound, body: .empty)
        }
        return conn.respond(status: .ok, body: .string(source))
            .putRespHeader(.contentType, "text/javascript; charset=utf-8")
            .putRespHeader(.cacheControl, "no-cache")
    }

    func stream(_ conn: Connection) async -> Connection {
        do {
            try await authorize(conn)
            try checkFetchOrigin(conn)
            let updates = try await host.subscribe(conn.params["id"] ?? "", owner: owner(conn))
            return conn.sseEvent { writer in
                let packets = livePackets(updates)
                defer { packets.cancel() }
                for await packet in packets.stream { try await writer.write(packet) }
            }
        } catch LiveError.notFound, LiveError.closed {
            // EventSource stops reconnecting on 204.
            return conn.respond(status: .noContent, body: .empty)
        } catch { return failure(error, conn: conn) }
    }

    func event(_ conn: Connection) async -> Connection {
        do {
            try await authorize(conn)
            try checkFetchOrigin(conn)
            let checked = try await csrfProtection()(conn)
            guard !checked.isHalted else { return failure(LiveError.unauthorized, conn: conn) }
            guard conn.getReqHeader(.contentType)?.lowercased().hasPrefix("application/json") == true,
                  case .buffered(let data) = conn.requestBody, data.count <= 65_536,
                  let event = try? JSONDecoder().decode(LiveEvent.self, from: data),
                  let revision = event.baseRevision, revision >= 0 else { throw LiveError.invalidEvent }
            let update = try await host.handle(conn.params["id"] ?? "", owner: owner(conn), event: event)
            return try conn.json(value: update).putRespHeader(.cacheControl, "no-store")
        } catch { return failure(error, conn: conn) }
    }

    /// Revoke open instances as part of logout or a permission change.
    func invalidate(_ conn: Connection) async {
        if let owner = conn.getSession(Self.ownerKey) { await host.invalidate(owner: owner) }
    }

    private func owner(_ conn: Connection) throws -> String {
        guard conn[RoostSessionKey.self] != nil,
              let owner = conn.getSession(Self.ownerKey), !owner.isEmpty else { throw LiveError.unauthorized }
        return owner
    }

    private func checkFetchOrigin(_ conn: Connection) throws {
        if conn.getReqHeader("Sec-Fetch-Site") == "cross-site" { throw LiveError.unauthorized }
    }

    private func failure(_ error: any Error, conn: Connection) -> Connection {
        let code = (error as? LiveError)?.rawValue ?? "eventFailed"
        let status: HTTPResponse.Status
        switch error as? LiveError {
        case .unauthorized: status = .forbidden
        case .notFound, .closed: status = .notFound
        case .stale, .reusedEventID, .notConnected: status = .conflict
        case .busy, .capacity: status = .serviceUnavailable
        case .invalidEvent: status = .unprocessableContent
        default: status = .internalServerError
        }
        return conn.respond(status: status, body: .string("{\"error\":\"\(code)\"}"))
            .putRespHeader(.contentType, "application/json")
            .putRespHeader(.cacheControl, "no-store")
    }
}

enum LivePageKey<View: Interactive>: AssignKey {
    typealias Value = PlaygroundLivePage<View>
}

/// Serves a live page's client script, update stream, and events. The page
/// itself comes from the request, put there by its routes' scope.
struct LiveController<View: Interactive>: Controller {
    enum Action: String, ControllerAction {
        case asset, stream, event
    }

    static func action(_ action: Action) -> Plug {
        switch action {
        case .asset: asset
        case .stream: stream
        case .event: event
        }
    }

    static func asset(_ conn: Connection) async throws -> Connection {
        try PlaygroundLivePage<View>.current(conn).asset(conn)
    }

    static func stream(_ conn: Connection) async throws -> Connection {
        try await PlaygroundLivePage<View>.current(conn).stream(conn)
    }

    static func event(_ conn: Connection) async throws -> Connection {
        try await PlaygroundLivePage<View>.current(conn).event(conn)
    }
}

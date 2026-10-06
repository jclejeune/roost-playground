import ESWLive
import Foundation

/// Carries a view's state from one preview process to the next when the code changes.
/// Only `Codable` states travel; others start fresh on every reload, as before.
final class PreservedState<State: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var seed: State?
    private var latest: State?

    init(seed: State?) { self.seed = seed }

    /// The state carried from the previous process, until a browser connects to it.
    /// Reloading the page after that mounts fresh, which is how a user resets.
    func seed(connected: Bool) -> State? {
        lock.withLock {
            defer { if connected { seed = nil } }
            return seed
        }
    }

    // ponytail: one shared "latest" across tabs; a single-user playground has one live tab.
    func record(_ state: State) { lock.withLock { latest = state } }

    /// JSON for the most recently rendered state, or nil when the state is not `Encodable`.
    func encodedLatest() -> Data? {
        guard let current = lock.withLock({ latest }), let value = current as? any Encodable else { return nil }
        return try? JSONEncoder().encode(value)
    }

    /// Nil when the state is not `Decodable` or its shape changed with the new code.
    static func decode(_ data: Data) -> State? {
        guard let type = State.self as? any Decodable.Type else { return nil }
        return (try? JSONDecoder().decode(type, from: data)) as? State
    }
}

/// A playground whose first mount may continue from carried state.
struct PreservingView<Page: LivePlayground>: LiveView {
    let page: Page
    let preserved: PreservedState<Page.State>

    func mount(_ context: LiveContext) async throws -> Page.State {
        if let seed = preserved.seed(connected: context.isConnected) { return seed }
        return try await page.mount(context)
    }

    func handleEvent(_ event: LiveEvent, state: Page.State) async throws -> Page.State {
        try await page.handleEvent(event, state: state)
    }

    func render(_ state: Page.State) -> ESWLiveRender {
        preserved.record(state)
        return page.render(state)
    }
}

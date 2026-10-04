import RoostPlayground

@main
struct TemplatedCounter: LivePlayground {
    func mount(_ context: LiveContext) async throws -> Int { 0 }
    func handleEvent(_ event: LiveEvent, state: Int) async throws -> Int {
        guard event.name == "increment" else { throw LiveError.invalidEvent }
        return state + 1
    }
    func render(_ state: Int) -> ESWLiveRender { renderCounterLive(count: state) }
}

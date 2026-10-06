/// The file `roost-playground new` writes: the smallest complete live playground.
public let starterPlayground = #"""
import RoostPlayground

@main
struct Counter: LivePlayground {
    func mount(_: LiveContext) async throws -> Int { 0 }

    func handleEvent(_ event: LiveEvent, state: Int) async throws -> Int {
        guard event.name == "increment" else { throw LiveError.invalidEvent }
        return state + 1
    }

    // The template uses `count` inside a string; formatters cannot see that reference.
    // swiftformat:disable:next unusedArguments
    func render(_ count: Int) -> ESWLiveRender {
        #live("""
        <main>
          <h1>Hello, Roost.</h1>
          <output>{count}</output>
          <button type="button" esw-click="increment">+1</button>
        </main>
        """)
    }
}

"""#

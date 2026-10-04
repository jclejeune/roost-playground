import RoostPlayground

@main
struct Counter: LivePlayground {
    static let title = "A little Swift, live."

    struct State: Sendable {
        var count = 0
        var name = ""
        var greeting = "Your next interaction runs in Swift."
    }

    func mount(_ context: LiveContext) async throws -> State { State() }

    func handleEvent(_ event: LiveEvent, state: State) async throws -> State {
        var state = state
        switch event.name {
        case "increment": state.count += 1
        case "decrement": state.count -= 1
        case "greet":
            state.name = event.value("name") ?? ""
            state.greeting = state.name.isEmpty ? "Tell me your name." : "Hello, \(state.name)!"
        default: throw LiveError.invalidEvent
        }
        return state
    }

    // The template uses state inside a string; formatters cannot see those references.
    // swiftformat:disable:next unusedArguments
    func render(_ state: State) -> ESWLiveRender {
        #live("""
        <main>
          <p class="muted">ONE FILE. A LIVE SWIFT APP.</p>
          <h1>A little Swift, live.</h1>
          <p class="muted">Edit this file and save. Your next idea is a rebuild away.</p>
          <section aria-label="Counter">
            <h2>State lives on the server.</h2>
            <div class="counter">
              <button type="button" esw-click="decrement" aria-label="Decrease">−</button>
              <output id="count" aria-live="polite">{state.count}</output>
              <button type="button" esw-click="increment" aria-label="Increase">+</button>
            </div>
          </section>
          <section aria-label="Greeting">
            <form esw-submit="greet">
              <label for="name">Your name</label>
              <div class="form-row"><input id="name" name="name" value={state.name} autocomplete="off" /><button type="submit">Say hello</button></div>
            </form>
            <p id="greeting" aria-live="polite">{state.greeting}</p>
          </section>
        </main>
        """)
    }
}

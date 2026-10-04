# Roost Playground

A live Swift application in one file, powered by ESW Live and Roost (the renamed Peregrine framework). Save it, let Swift compile, and see the new version in your browser.

```sh
./playground Examples/Counter.swift
```

The browser opens at **http://127.0.0.1:4567**. Click the counter, submit the form, then edit `Examples/Counter.swift` and save. The preview updates automatically. A failed build shows its diagnostics while the last working page stays interactive.

## One file

```swift
import RoostPlayground

@main
struct Counter: LivePlayground {
    func mount(_ context: LiveContext) async throws -> Int { 0 }

    func handleEvent(_ event: LiveEvent, state: Int) async throws -> Int {
        guard event.name == "increment" else { throw LiveError.invalidEvent }
        return state + 1
    }

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
```

`LivePlayground` is an ordinary ESW `LiveView` with `init()` and an application entry point. It supplies the Roost server, session middleware, page layout, and ESW live client. Set `static let title` to change the page title. State and event handling remain Swift; rendering uses the same `#live` macro as a full application.

SwiftFormat sees the template as a string and may remove parameters referenced only inside it. Keep the `unusedArguments` guard above `render` when using format-on-save.

The fuller [counter example](Examples/Counter.swift) includes form submission. The [template example](Examples/Templated/Counter.swift) uses a separate `.live.heex` file:

```sh
./playground Examples/Templated/Counter.swift
```

Optional `.heex` and `.esw` files in the input's sibling `Views/` directory are compiled with `ESWBuildPlugin`. Nested directories work; adding, editing, deleting, or recreating a template triggers a rebuild.

## Local setup

This first version targets **macOS 14+ and Swift 6.3+**. It consumes the current local ESW Live and Roost development code, so keep these checkouts as siblings:

```text
swift-projects/
├── esw/                     # Includes the ESWLive product
├── Nexus/
├── Peregrine/               # Current checkout folder; exports the Roost library
└── roost-playground/
```

The launcher generates the example's Swift package for you. Its first run resolves dependencies and compiles both the runner and preview. Later runs reuse their build caches. This is currently a local development project; the manifests have not been converted to published ESW Live releases. A private adapter in `Sources/RoostPlayground/` connects ESW Live to Roost; this keeps the playground independent of the older `ESWLivePeregrine` integration during the framework rename.

```sh
./playground /path/to/Counter.swift --port 4568 --no-open
./playground --help
```

Use `--port` for another browser-shell port and `--no-open` to print the address without opening a browser. Paths containing spaces or quotes are supported. **Ctrl-C** stops the runner, compiler subprocesses, and preview servers. A second runner for the same input is rejected; different inputs can use different shell ports.

## Appearance

The playground uses the Roost reading-queue demo's palette, Avenir headings, blue controls, and orange bird mark. The assets are bundled locally.

- [Shared Roost theme](Sources/PlaygroundTheme/Resources/roost.css): colors, typography, controls, and the default preview layout. Both the browser shell and standalone previews use this stylesheet.
- [Playground shell styles](Sources/PlaygroundCLI/Resources/playground.css): file bar, build status, and diagnostics.

The theme is adapted from Roost's `examples/Roost/Public/css/app.css`, with its original `images/roost.png` logo. Restart the launcher after editing bundled theme assets.

## Reload behavior

- The input Swift file and its `Views/` directory are watched by content, with a short debounce for saves.
- The browser shell stays open while a candidate version compiles in the background.
- Returning to an exact previous version reuses its saved executable and resources without invoking Swift. The session keeps the eight most recently used successful builds; the status bar shows **Cached** on reuse.
- Reuse requires identical Swift and template contents, local package sources/resources, manifests, and dependency resolutions. A similar file is not a match. Dependency changes are checked on the next source/template edit; restart the runner after changing the toolchain.
- The candidate must start, answer its readiness token, and render successfully before replacing the active page. A stale build is discarded when a newer edit exists.
- Compile errors and startup failures preserve the previous page and its live state. Diagnostics refer to the original source and template paths.
- **Successful code reloads reset live state**, including cached versions. Each reload starts a fresh application process.
- A preview crash is reported. Save another edit to start a new version.

The shell and worker bind to loopback. Each preview runs on its own port inside the shell's iframe, and playground sessions use a cookie specific to that input. The browser polls a read-only status endpoint; editing happens in your editor.

## Build artifacts

All SwiftPM build products live under:

```text
~/Library/Caches/roost-playground/<checkout-id>/
├── runner/                  # CLI build
└── previews/<input-id>/      # Generated package
    ├── .build/              # SwiftPM dependencies and incremental build products
    ├── logs/                # Compiler and preview output
    ├── runs/                # Isolated copies for active preview processes
    └── versions/<hash>/     # Up to eight successful builds for this session
```

This keeps signed bundles outside File Provider-managed source folders such as synced `Documents`. Each running preview owns a copy of its executable and resource bundles, so another build cannot change its loaded resources.

**Ctrl-C and SIGTERM remove the saved-version cache** after stopping the preview processes and removing their staged copies. SwiftPM's dependency/incremental cache and logs remain for later launches. A forced kill cannot run cleanup; the next runner removes leftover saved versions after acquiring the input's lock. Saved versions are never reused across runner sessions.

Set `ROOST_PLAYGROUND_CACHE` to relocate the cache. Keep it outside synced folders. `ROOST_PLAYGROUND_ROOT` locates this checkout when invoking a compiled CLI directly; the launcher sets it automatically.

SwiftPM currently emits upstream package-identity warnings for the local ESW/Nexus overrides and the two SwiftSyntax repository URLs. The adjacent projects need coordinated dependency changes before replacing this local-checkout setup with distribution packaging.

## Checks

```sh
./scripts/check.sh test
cd BrowserTests
npm ci
npm test
```

Browser acceptance uses an installed Google Chrome on macOS, or Playwright's Chromium (`npx playwright install chromium`). Set `PLAYWRIGHT_EXECUTABLE_PATH` to use another Chromium binary. The tests own their input copies, ports, and processes; screenshots and logs go in `BrowserTests/artifacts/`.

See [validation notes](docs/validation.md) for the exercised behaviors and current limits.

# Roost Playground

A live Swift application in one file, powered by ESW Live and Roost (the renamed Peregrine framework). Save it, let Swift compile, and see the new version in your browser.

**[v0.1.0-alpha.3](https://github.com/roost-framework/roost-playground/releases/tag/v0.1.0-alpha.3) is an alpha preview** for **macOS 14+ and Swift 6.3+**. It builds against published ESW 1.5, Roost 2.0, and Nexus 2.0.

## Quick start

Install the command with [Mint](https://github.com/yonaskolb/Mint), fetch the counter example, and run it:

```sh
mint install roost-framework/roost-playground@v0.1.0-alpha.3
curl -O https://raw.githubusercontent.com/roost-framework/roost-playground/v0.1.0-alpha.3/Examples/Counter.swift
roost-playground Counter.swift
```

Mint links the command into `~/.mint/bin`; add that directory to your `PATH`. To upgrade, install a newer release tag the same way.

Or run it from a clone:

```sh
git clone https://github.com/roost-framework/roost-playground.git
cd roost-playground
./playground Examples/Counter.swift
```

The browser opens at **http://127.0.0.1:4567**. Click the counter, submit the form, then edit `Counter.swift` and save. The preview updates automatically. A failed build shows its diagnostics while the last working page stays interactive.

The first preview downloads and compiles ESW, Roost, and their dependencies, which takes a couple of minutes. Later edits rebuild incrementally in seconds.

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

The fuller [counter example](Examples/Counter.swift) includes form submission. The [template example](Examples/Templated/Counter.swift) uses a separate `.live.heex` file. From a clone:

```sh
./playground Examples/Templated/Counter.swift
```

Optional `.heex` and `.esw` files in the input's sibling `Views/` directory are compiled with `ESWBuildPlugin`. Nested directories work; adding, editing, deleting, or recreating a template triggers a rebuild.

## Options

```sh
roost-playground /path/to/Counter.swift --port 4568 --no-open
roost-playground --help
```

From a clone, use `./playground` in place of `roost-playground`. Use `--port` for another browser-shell port and `--no-open` to print the address without opening a browser. Paths containing spaces or quotes are supported. **Ctrl-C** stops the runner, compiler subprocesses, and preview servers. A second runner for the same input is rejected; different inputs can use different shell ports.

## Appearance

The playground uses the Roost reading-queue demo's palette, Avenir headings, blue controls, and orange bird mark. The assets are bundled locally.

- [Shared Roost theme](Sources/PlaygroundTheme/Resources/roost.css): colors, typography, controls, and the default preview layout. Both the browser shell and standalone previews use this stylesheet.
- [Playground shell styles](Sources/PlaygroundCLI/Resources/playground.css): file bar, build status, and diagnostics.

The theme is adapted from Roost's `examples/Roost/Public/css/app.css`, with its original `images/roost.png` logo. From a clone, restart the launcher after editing bundled theme assets.

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
~/Library/Caches/roost-playground/<id>/
├── runner/                  # CLI build (clone launcher only)
└── previews/<input-id>/      # Generated package
    ├── .build/              # SwiftPM dependencies and incremental build products
    ├── logs/                # Compiler and preview output
    ├── runs/                # Isolated copies for active preview processes
    └── versions/<hash>/     # Up to eight successful builds for this session
```

This keeps signed bundles outside File Provider-managed source folders such as synced `Documents`. Each running preview owns a copy of its executable and resource bundles, so another build cannot change its loaded resources.

**Ctrl-C and SIGTERM remove the saved-version cache** after stopping the preview processes and removing their staged copies. SwiftPM's dependency/incremental cache and logs remain for later launches. A forced kill cannot run cleanup; the next runner removes leftover saved versions after acquiring the input's lock. Saved versions are never reused across runner sessions.

Set `ROOST_PLAYGROUND_CACHE` to relocate the cache. Keep it outside synced folders.

## Development

A clone compiles previews against its own `RoostPlayground` sources, so library edits show up on the next rebuild. An installed command instead fetches the release tag it was built from. `ROOST_PLAYGROUND_ROOT` locates the clone when invoking a compiled CLI directly; the launcher sets it automatically.

To develop ESW, Nexus, Roost, and Spectro alongside the playground, set `ROOST_ECOSYSTEM_PATH` to the folder holding their `esw/`, `Nexus/`, `Peregrine/`, and `Spectro/` checkouts. Roost reads the same variable, so every package uses the same local copies.

A private adapter in `Sources/RoostPlayground/` connects ESW Live to Roost; this keeps the playground independent of the older `ESWLivePeregrine` integration during the framework rename.

SwiftPM currently warns that ESW and Spectro reach SwiftSyntax through two repository URLs (`swiftlang/` and `apple/`). This needs a coordinated change upstream.

### Checks

```sh
./scripts/check.sh test
cd BrowserTests
npm ci
npm test
```

Browser acceptance uses an installed Google Chrome on macOS, or Playwright's Chromium (`npx playwright install chromium`). Set `PLAYWRIGHT_EXECUTABLE_PATH` to use another Chromium binary. The tests own their input copies, ports, and processes; screenshots and logs go in `BrowserTests/artifacts/`.

See [validation notes](docs/validation.md) for the exercised behaviors and current limits.

### Releasing

An installed command compiles previews against the release named by `playgroundVersion` in `Sources/PlaygroundCore/Workspace.swift`. Before tagging:

1. Set `playgroundVersion` to the new version, without the `v` prefix (for example `0.1.0-alpha.4`).
2. Update the version in this README's Mint and `curl` commands.
3. Commit, tag with the `v` prefix (`v0.1.0-alpha.4`), and push the tag.
4. Run `mint install roost-framework/roost-playground@<tag>` and build a preview outside any clone.

# Roost Playground

The user approved a separate project for the previously proposed single-file Swift live-view workflow. This repository is a sibling of ESW and Peregrine; it consumes their current local libraries without modifying either checkout.

## User contract

Run `./playground Examples/Counter.swift` to open a local browser preview. A file imports `RoostPlayground` and declares `@main struct Counter: LivePlayground`, with the ordinary typed `mount`, `handleEvent`, and `render` methods. The protocol refines `LiveView` and supplies application startup. Existing `#live` and generated `.live.heex` functions remain the rendering APIs. No interpretation of Swift expressions or separate playground language is introduced.

The runner watches the chosen file and optional sibling `Views` templates. Saved changes compile in a cached SwiftPM workspace outside Documents. A stable browser shell reports building, ready, and error states and embeds the actual Roost application. Compilation errors retain the last working preview. A successful candidate must answer a unique health token before replacing the previous process. A new code generation remounts state. State-preserving code reload is outside this version.

## Architecture

- `RoostPlayground` library: `LivePlayground: LiveView`, default startup, page layout, private generic `RoostApp`, standard sessions/CSRF, ESWLive adapter, readiness endpoint.
- `PlaygroundCore`: CLI configuration, source snapshots, deterministic cache workspaces, process lifecycle, and a main-actor supervisor. No HTTP/UI dependency is needed in core tests.
- `roost-playground` executable: a Hummingbird development shell on `127.0.0.1`, read-only status endpoint, browser assets, and supervisor lifecycle. It has no browser endpoint that accepts source or executes commands.
- Child applications use unique loopback ports and copied executable/resource bundles. Failed and obsolete builds never replace the working generation. The browser shell reloads its iframe only when the ready generation changes.
- `playground` launcher caches its own SwiftPM artifacts outside synced folders and locates its repository independently of cwd. The generated workspace uses the same rule.

The initial implementation targets macOS 14+ and Swift 6.3+. It uses local sibling ESW/Peregrine/Nexus checkouts; distribution with released dependency versions is separate work. The CLI requires only the Swift toolchain. Playwright/Node are test dependencies.

Implementation adjustment: the neighboring Peregrine checkout was renamed to the Roost module during development. The playground consumes that Roost product and carries a private adaptation of ESW's original server adapter, with its route tests. This avoids editing either neighboring repository while their integration package catches up. The user then requested the RoostPlayground name: the repository, library, CLI, environment variables, cache namespace, browser branding, and examples follow that name. The `LivePlayground` protocol is unchanged.

## Failure and lifecycle contract

Missing/unreadable input, invalid options, and an occupied shell port fail explicitly. Compiler diagnostics refer back to the original source. Atomic saves, template deletion/recreation, and edits during compilation trigger the latest snapshot. Startup failure keeps the previous application alive. A process crash is visible. Logs shown in the browser are bounded and inserted as text. SIGINT/SIGTERM shut down the supervisor and its workers; a per-input workspace lock prevents concurrent writers to one cache.

## Acceptance

Run a real one-file counter/form in headless Chrome. Edit the source and verify automatic rebuild and state reset without shell navigation. Break compilation and verify diagnostics while the old counter remains interactive. Fix it and verify recovery. Also exercise an initially broken file, template-only edits, atomic saves, paths with spaces, candidate startup failure, and process cleanup. Capture and inspect the ready and failed-build screens. Unit tests cover configuration, snapshot fingerprints, safe generated source/manifests, cache ownership, and lock exclusion.

The source examples must remain normal reusable Swift live views. No change to ESW, Peregrine, Nexus, or Spectro is part of this project.

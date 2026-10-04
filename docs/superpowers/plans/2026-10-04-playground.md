# Roost Playground Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan natively, followed by one fresh review. The user already authorized the design and requested a separate project; continue implementation without a new approval gate.

**Goal:** Deliver a standalone single-file Roost live-view playground with working preview, rebuild-on-save, errors, and browser acceptance.

**Architecture:** A small Swift runtime library boots an ordinary ESWLive/Roost page. A development supervisor compiles immutable source snapshots into a private cache and promotes healthy worker processes; a stable browser shell embeds the current worker and displays status.

**Tech Stack:** Swift 6.3+, macOS 14+, Foundation, CryptoKit, Hummingbird 2, local ESWLive and Roost, Swift Testing, Playwright.

**Spec:** `docs/superpowers/specs/2026-10-04-playground-design.md`

## Global Constraints

- All authored changes belong to the new sibling `roost-playground` repository.
- Swift 6.3+, macOS 14+, Swift 6 concurrency checking; no unchecked Sendable added.
- Build workspaces stay in the local cache, outside file-provider-managed source directories.
- Only loopback listeners; browser status is read-only and source is compiled locally.
- Failed builds retain the last working preview; successful reloads reset state.
- Execute natively; obtain one fresh review after implementation.

## Review Focus

1. A path containing spaces or quotes must survive generated Swift literals and process arguments; Task 1 tests both.
2. An edit during compilation must not promote stale code; Task 3 and browser acceptance test latest-snapshot behavior.
3. A valid compilation whose process cannot become healthy must not retire the old preview; Task 3 tests startup failure.
4. Resource bundles must travel with immutable worker executables; Task 2/3 acceptance clicks the bundled client after replacement.
5. Shutdown must stop children and release the workspace lock; Task 3/4 inspect child processes and restart the same input.

## Task 1: Configuration and cached workspace

Files: `Package.swift`, `Sources/PlaygroundCore/Configuration.swift`, `SourceSnapshot.swift`, `Workspace.swift`, `Tests/PlaygroundCoreTests/WorkspaceTests.swift`, `playground`.

Interfaces: `Configuration(arguments: [String], currentDirectory: URL, packageRoot: URL, cacheRoot: URL?)`; `SourceSnapshot.capture(configuration:)`; `Workspace.prepare(snapshot:)`; `Workspace.acquire()`.

- [x] Write tests for invalid/missing input, port bounds, content changes with equal timestamps, deleted templates, literal escaping, unchanged writes, separate cache identities, and duplicate locks. Observe failure before implementation.
- [x] Generate a SwiftPM package consuming the root `RoostPlayground` product and ESW build plugin. Emit `#sourceLocation(file: String(reflecting: input.path), line: 1)` before user code; keep filenames and template paths in the snapshot.
- [x] Implement the cache launcher and run `scripts/check.sh test --filter WorkspaceTests`; require all workspace cases to pass.

## Task 2: Real single-file runtime

Files: `Sources/RoostPlayground/LivePlayground.swift`, `Examples/Counter.swift`, `Examples/Templated/Counter.swift`, `Examples/Templated/Views/counter.live.heex`.

Interfaces: `LivePlayground: LiveView` adds `init()`, `static var title: String`, and default `static func main() async throws`. It boots a private `RoostApp` with standard browser plugs and the live adapter. GET `/__playground/health` returns the runner's unique environment token. The user requested RoostPlayground naming after the framework rename during implementation.

- [x] Compile an example through the generated workspace, then fetch initial HTML and click its live counter in browser acceptance.
- [x] Add a template-based example with `renderCounterLive(count:)` and verify editing only its template changes the next preview.

## Task 3: Supervisor and browser shell

Files: `Sources/PlaygroundCore/ManagedProcess.swift`, `Supervisor.swift`, `Status.swift`; `Sources/PlaygroundCLI/Command.swift`, `Resources/index.html`, `Resources/playground.js`, `Resources/playground.css`.

Interfaces: `@MainActor Supervisor(configuration:)`, `run() async`, `shutdown() async`, `status: PlaygroundStatus`; `PlaygroundStatus` is Codable/Sendable with phase, filename, generation, previewURL, diagnostics, and build duration.

- [x] Compile snapshots using array process arguments and bounded file-backed diagnostics. Keep processes actor-isolated; cancellation closes owned children.
- [x] Start candidates from unique executable/resource copies and require matching readiness tokens. Re-read inputs before promotion. Failed/stale candidates are stopped; only healthy current candidates replace the worker.
- [x] Serve shell/status/assets on loopback, with no-store status and hostname checks. Poll status in the browser, preserve the existing iframe during errors, and replace it only for a new ready generation.
- [x] Make the watcher resilient to atomic saves, deleted/recreated sources/templates, runtime crashes, and shutdown.

## Task 4: Acceptance and handoff

Files: `BrowserTests/acceptance.mjs`, `BrowserTests/package.json`, `README.md`, `docs/validation.md`.

- [x] Run unit tests, compile examples, and execute real-browser success/error/recovery tests against owned processes and temporary copies of source files.
- [x] Verify original-source diagnostics, last-good interactivity, state reset, startup failure, template edits, and worker cleanup. Capture ready/error screenshots and visually inspect them.
- [x] Run shell/JS syntax and whitespace checks, then request one read-only whole-project review. Fix material findings and rerun the checks they affect.
- [x] Document one-command usage, current dependencies, cache location, reload semantics, and verification evidence. Commit the isolated project locally; do not publish or push it.

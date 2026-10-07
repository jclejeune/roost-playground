# Validation

Environment: local runs use macOS with Swift 6.4 (Xcode 27.2 beta toolchain); CI runs on GitHub's macOS 15 image with Swift 6.3.3 and the Xcode 26.3 SDK. Swift 6 language mode, macOS 14 deployment target.

## Automated checks

`./scripts/check.sh test` covers argument errors, `new` file creation, relative input resolution, build-progress parsing, one-builder-at-a-time locking for the shared preview package, README/version consistency, content fingerprints with unchanged timestamps, template removal, nested paths, distinct cache identities, escaped Swift literals, incremental writes, lock exclusion, bounded process output, exit status, and process-group cleanup.

Session-cache tests cover independent executable/resource copies, least-recently-used eviction, missing or incomplete artifacts, stale-session cleanup, and hashes that change with local source/resource contents or dependency resolution, even when timestamps stay unchanged.

The runtime tests also exercise carried state (a `Codable` state travels to the next process until a browser connects; other or reshaped states start fresh) and its private Roost adapter: session ownership, cross-site and CSRF rejection, event validation, duplicate-event replay, stale revisions, revocation, and bundled browser assets. These are the original ESW integration contracts adapted to the renamed framework.

`npm --prefix BrowserTests test` exercises the actual generated Swift package, Roost worker, ESW JavaScript bundle, and browser shell. Its acceptance assertions cover:

- Counter and form events, isolated session cookies, Host rejection, narrow-screen layout, duplicate-runner rejection.
- Compilation failure with the original quoted source path and continued interaction with the previous preview.
- Macro-expansion errors appear before dependency warnings and contain readable text without terminal escape codes.
- Atomic saves, successful reload with fresh state for a non-`Codable` state, stable parent page, and retirement of the old worker.
- A `Codable` state (count and form text) survives a code reload; a browser reload resets it; a changed state shape starts fresh.
- Edits during compilation, failed candidate startup, deleted/recreated sources, and recovery after a worker crash.
- SIGINT, workspace-lock release, restarting in the same browser tab, and an initially invalid file.
- File-based HEEx rendering, template-only changes, template diagnostics, deletion/recreation, and SIGTERM cleanup.
- An A → B → A undo after an obsolete compilation completes, without another save to unstick the watcher.
- Exact source and HEEx rollbacks reuse successful builds; the source rollback leaves the compiler log untouched, restores the correct page with fresh state, and handles a live event.
- Failed workers never enter the cache, duplicate runners cannot clear it, and SIGINT/SIGTERM remove saved versions. A new runner must compile again while retaining SwiftPM's incremental cache.

The acceptance suite writes ready, mobile, compiler-error, macro-error, and cached-version screenshots to `BrowserTests/artifacts/`.

## Verified on 2026-10-04

- After the RoostPlayground rename, `./scripts/check.sh test` passed all 12 Swift tests: 10 workspace/process/diagnostic tests and 2 adapter contracts.
- `npm --prefix BrowserTests test` passed all 11 acceptance checkpoints against the renamed library, CLI, environment variables, and fresh cache. Both the inline and HEEx examples compiled and handled real browser events.
- Ready desktop (1280 × 960), mobile (390 × 844), and compiler-error captures were visually inspected. Roost branding, readable source diagnostics, the retained live preview, and the narrow-screen form were confirmed. The browser assertions also checked for horizontal overflow and uncaught JavaScript errors.
- A separate read-only review found an A → B → A undo that could strand the watcher on a discarded compilation. The browser regression reproduced the failure before the fix and passed afterward, including in the final complete suite.
- The documented `./playground Examples/Counter.swift --no-open` launcher passed with a relative input after the rename. Its staged executable and all 9 resource bundles passed `codesign --verify --strict` under `~/Library/Caches/roost-playground/`; Ctrl-C exited cleanly and closed the preview listener. An occupied-port smoke check also passed before the final branding rename.
- Shell and JavaScript syntax checks and staged whitespace checks passed. No neighboring repository was edited for this project.

## Rebuild diagnostics regression, 2026-10-04

A save-time SwiftFormat rewrite removed the `state` binding because its uses occur inside the `#live` template string. The resulting colored Swift macro diagnostics bypassed the location parser, leaving dependency warnings at the top of the error panel. A regression using the captured diagnostic format failed before the fix. Terminal escape sequences are now removed before parsing, including for tool failures with no source location. Replaying the original build log then displayed the actual missing-variable error first.

The example and README now guard `render` with `swiftformat:disable:next unusedArguments`. SwiftFormat was run against a copy of the example and preserved the binding. The user's existing preview rebuilt successfully after restoring it.

Final verification passed all **14 Swift tests** and **12 browser acceptance checkpoints**. The new macro-error capture was visually inspected: the error and source context appear first while the previous counter remains interactive. Existing runner processes need one restart to load the diagnostic parser change.

## Roost demo styling, 2026-10-04

The shell and default previews now share a bundled stylesheet adapted from the Roost reading-queue demo. The logo is a byte-for-byte copy of the demo asset. No external fonts or image requests are needed.

- All 14 Swift tests and 12 browser acceptance checkpoints passed with the shared theme bundle, including replacement workers and the file-based HEEx example.
- A live comparison with the demo at `127.0.0.1:4000` confirmed matching values for all eight color tokens and the heading font in both the shell and preview.
- Fresh browser views at 1280, 390, and 320 pixels were captured and visually reviewed; the logo, controls, form layout, and footer fit without horizontal overflow. Counter and form events, keyboard focus, local asset content types, and invalid-field border styling were checked.
- Reviewed captures are in `BrowserTests/artifacts/roost-theme-1280.png`, `roost-theme-390.png`, `roost-theme-320.png`, and `macro-error.png`; the reference is `roost-demo-reference.png`.

SwiftPM also synchronized the lockfile with the neighboring Roost manifest's existing Spectro 2.0.0 requirement. The SwiftSyntax revision is unchanged; its resolved repository URL follows the updated dependency graph.

## Session build reuse, 2026-10-04

- All **18 Swift tests** and **14 browser acceptance checkpoints** passed. The new browser cache assertion failed against the original runner before the supervisor integration was added.
- In the measured A → B → A sequence, B compiled and became ready in **6,990 ms**; A reused its saved executable and resource bundles in **941 ms**. These are supervisor durations, excluding the save debounce and browser polling. The compiler log's modification time was unchanged on reuse.
- Reuse restored the expected heading, reset the counter, and handled a real browser event. The `Cached · 0.9s` status and restored preview were visually reviewed in `BrowserTests/artifacts/cached-version.png`.
- Returning to the original HEEx template was also a cache hit. Failed startup was not cached, and an attempted duplicate runner left the existing cache usable.
- SIGTERM left no staged workers or saved versions and preserved the SwiftPM cache. A new session compiled again; SIGINT also removed its saved versions and closed its worker.
- JavaScript syntax and whitespace checks passed. Tests used their own source copies and processes.

## Release 1.0.0, 2026-10-06

- `./scripts/check.sh test` passed 25 Swift tests locally (Swift 6.4) and in CI (Swift 6.3.3).
- The browser acceptance suite passed locally and in CI, including the new carried-state checkpoint.
- A second input file built in 7.4 s against the shared preview package, versus 82 s for the first cold build. Two runners for different files built concurrently, took turns on the package lock, and each served its own page.
- The status bar reported "Fetching packages…" and "Building n of N" during builds, including Swift 6.4's thin-space step counter.
- `roost-playground new` wrote the starter, which built and rendered; a second `new` for the same file was refused.
- With Spectro 2.1.1 resolved, the build reports no conflicting SwiftSyntax identity.
- The tag workflow checks `playgroundVersion`, installs the tag with Mint on macOS 26 with Xcode's toolchain, and builds a starter outside any checkout.
- On macOS 15 with the swift.org 6.3.3 toolchain, Mint's release build of the command stopped at launch: `Symbol not found: _$sScfsE25isIsolatingCurrentContextSbSgyF` in `/usr/lib/swift/libswift_Concurrency.dylib`. The same toolchain's debug builds, which the clone launcher uses, pass the whole acceptance suite there.

## Release 1.0.1, 2026-10-07

- A cold preview cache measured 1.9 GB: 1.3 GB of compiled dependencies and 615 MB of dependency clones and checkouts. Building without debug info (`-gnone`) only saved about 100 MB, so previews keep it.
- Installed copies now share one cache folder. A playground started from a clone removed a stale cache folder and kept its own; `roost-playground clean` then removed the remaining cache and reported 2.68 GB freed.
- Unit tests cover the cache location for installed copies and clones, pruning (deleted clones and unmarked caches go; the current, shared installed, live-clone, and locked caches stay), and `clean` skipping a locked cache.
- The browser acceptance suite passed locally.

## Release 1.0.3, 2026-10-07

- The playground's routes go to Roost 2.1 controllers: `LiveController` serves a live page's client script, update stream, and events, and `PlaygroundController` serves the page and the supervisor's health and state checks. Request logs and traces name the action, such as `LiveController<…>.event`.
- Controller actions are static, so their state travels in the request: a live page's routes assign the page in their scope, and the application assigns its live page, preserved state, and supervisor token in its plugs.
- All 29 Swift tests passed, including the live-route contracts for session ownership, cross-site and CSRF rejection, event validation, replay, stale revisions, and revocation. The browser acceptance suite passed in CI. Locally, 13 of 14 checkpoints passed: the cache checkpoint's final shutdown exceeded its 8 s limit under background CPU priority, and failed the same way on the unmodified 1.0.2 code.

## Release 1.0.2, 2026-10-07

- Nexus 2.1.0 and Spectro 2.2.0 put their optional dependencies behind default package traits, and Roost 2.1.1 turns off Nexus's `Vapor` trait. The playground requires Roost 2.1.1 and also turns off Nexus's defaults on its direct dependency. A fresh resolve fetches 43 packages and 542 MB of sources instead of 49 and 730 MB; Vapor, routing-kit, multipart-kit, console-kit, and websocket-kit are gone. Spectro keeps its defaults in Roost because `roost spectro` runs the app's own `spectro` command.
- SwiftPM refused to re-resolve a preview package left by 1.0.1 (Nexus 2.0.0 pinned and checked out): "Disabled default traits … on package 'nexus' … that declares no traits." The runner now drops the shared package's pins, workspace state, and checkouts once when a build fails before "Building for", then retries. Over a real 1.0.1 cache, the preview re-resolved to Roost 2.1.1 and Nexus 2.1.0 and rendered (148 s for that first build).
- Clones with old checkouts resolve normally with the committed `Package.resolved`.

## Release 1.0.4, 2026-10-07

- Spectro 2.3.0 puts Noora behind a `RichTerminal` trait, and Roost 2.1.2 enables only Spectro's `CLI` trait, so `roost spectro` builds the app's own spectro with plain-text output. With Roost 2.1.2, a fresh playground resolve fetches 40 packages and 453 MB of sources, down from 43 and 542 MB in 1.0.2; Noora is gone.
- The runtime uses ESW 1.6's `Interactive` name, so the build has no deprecation warnings.

## Limits

Installing with Mint needs macOS 26 or later; on macOS 14 and 15, run from a clone (see the release 1.0.0 notes above).

This is a macOS first version. It watches the selected Swift file and template directory; edits to dependency repositories or additional Swift files are outside the watch set. There is no browser editor, arbitrary package dependency UI, state migration, Linux validation, or remote execution service. The first cold build includes the framework dependency graph; later edits compile incrementally.

Spectro 2.1.1 depends on SwiftSyntax through the same `swiftlang/` URL as ESW, so SwiftPM no longer reports a conflicting package identity.

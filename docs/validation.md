# Validation

Environment: macOS, Swift 6.4 (Xcode 27.2 beta toolchain), Swift 6 language mode, macOS 14 deployment target. The Swift 6.3 minimum in the manifest has not been separately exercised with a 6.3 toolchain.

## Automated checks

`./scripts/check.sh test` covers argument errors and relative input resolution, content fingerprints with unchanged timestamps, template removal, nested paths, distinct cache identities, escaped Swift literals, incremental writes, lock exclusion, bounded process output, exit status, and process-group cleanup.

The runtime tests also exercise its private Roost adapter: session ownership, cross-site and CSRF rejection, event validation, duplicate-event replay, stale revisions, revocation, and bundled browser assets. These are the original ESW integration contracts adapted to the renamed framework.

`npm --prefix BrowserTests test` exercises the actual generated Swift package, Roost worker, ESW JavaScript bundle, and browser shell. Its acceptance assertions cover:

- Counter and form events, isolated session cookies, Host rejection, narrow-screen layout, duplicate-runner rejection.
- Compilation failure with the original quoted source path and continued interaction with the previous preview.
- Atomic saves, successful reload with fresh state, stable parent page, and retirement of the old worker.
- Edits during compilation, failed candidate startup, deleted/recreated sources, and recovery after a worker crash.
- SIGINT, workspace-lock release, restarting in the same browser tab, and an initially invalid file.
- File-based HEEx rendering, template-only changes, template diagnostics, deletion/recreation, and SIGTERM cleanup.
- An A → B → A undo after an obsolete compilation completes, without another save to unstick the watcher.

The acceptance suite writes ready, mobile, and compiler-error screenshots to `BrowserTests/artifacts/`.

## Verified on 2026-10-04

- After the RoostPlayground rename, `./scripts/check.sh test` passed all 12 Swift tests: 10 workspace/process/diagnostic tests and 2 adapter contracts.
- `npm --prefix BrowserTests test` passed all 11 acceptance checkpoints against the renamed library, CLI, environment variables, and fresh cache. Both the inline and HEEx examples compiled and handled real browser events.
- Ready desktop (1280 × 960), mobile (390 × 844), and compiler-error captures were visually inspected. Roost branding, readable source diagnostics, the retained live preview, and the narrow-screen form were confirmed. The browser assertions also checked for horizontal overflow and uncaught JavaScript errors.
- A separate read-only review found an A → B → A undo that could strand the watcher on a discarded compilation. The browser regression reproduced the failure before the fix and passed afterward, including in the final complete suite.
- The documented `./playground Examples/Counter.swift --no-open` launcher passed with a relative input after the rename. Its staged executable and all 9 resource bundles passed `codesign --verify --strict` under `~/Library/Caches/roost-playground/`; Ctrl-C exited cleanly and closed the preview listener. An occupied-port smoke check also passed before the final branding rename.
- Shell and JavaScript syntax checks and staged whitespace checks passed. No neighboring repository was edited for this project.

## Limits

This is a local macOS first version with sibling-checkout dependencies. It watches the selected Swift file and template directory; edits to dependency repositories or additional Swift files are outside the watch set. There is no browser editor, arbitrary package dependency UI, state migration, Linux validation, or remote execution service. The first cold build includes the framework dependency graph; later edits compile incrementally.

Upstream SwiftPM identity warnings remain visible. No neighboring repository was changed to suppress them.

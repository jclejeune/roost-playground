# Session build reuse

The user requested hash-based rollback without recompilation and cleanup when the server stops. Implement that behavior with an exact-content cache of successful preview artifacts; similar source is not a cache hit.

The existing Swift/template snapshot fingerprint remains the source identity. Combine it with local package inputs (manifests, lockfiles, Sources, and Plugins in the playground, ESW, Roost, and Nexus checkouts) and the generated package's resolution. The cache belongs to one runner, so it never crosses toolchain/environment sessions. Local package changes invalidate reuse when the next source edit is handled. Restart the runner after changing the toolchain; dependency-only watching remains outside this feature.

Keep up to eight successful executable/resource snapshots, evicting the least recently used. Copy a cached snapshot into an isolated worker directory and run the existing health/render/current-source checks before promotion. Reuse starts a fresh worker and resets live state, just like a successful compilation. Failed or stale candidates do not enter the cache; errors retain the working preview. Missing executables or resource bundles fall back to compilation. A cached worker that fails to start is evicted and its diagnostics are shown. Expose the build hash and cache-hit status for diagnostics and show cached reuse in the browser status.

Stop owned processes before clearing saved versions, then release the input's lock. Clear leftovers from an unclean exit after acquiring that same lock on the next start. SIGKILL cannot execute cleanup. Keep SwiftPM's compilation/dependency cache and logs; the new saved-version cache is session-scoped.

Validation: exercise cache isolation, LRU eviction, missing artifacts, cleanup, and dependency/resource hash invalidation in Swift tests. Real-browser A-to-B-to-A and template rollback must leave the compiler log unchanged, restore the correct UI with fresh state, and keep live events working. Verify SIGINT/SIGTERM cleanup and that a restarted runner cannot hit the previous session's saved versions.

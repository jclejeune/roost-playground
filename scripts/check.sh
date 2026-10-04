#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
checkout_id="$(printf '%s' "$project_root" | shasum -a 256 | cut -c 1-16)"
cache_root="${ROOST_PLAYGROUND_CACHE:-$HOME/Library/Caches/roost-playground/$checkout_id}"
action="${1:-test}"
if [[ $# -gt 0 ]]; then shift; fi
case "$action" in
    test|build) exec swift "$action" --package-path "$project_root" --scratch-path "$cache_root/runner" "$@" ;;
    bin-path) exec swift build --package-path "$project_root" --scratch-path "$cache_root/runner" --show-bin-path "$@" ;;
    *) printf 'Usage: %s [test|build|bin-path] [SwiftPM options]\n' "$0" >&2; exit 2 ;;
esac

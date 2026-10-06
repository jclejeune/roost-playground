#!/bin/bash
# Create a starter playground outside any checkout, build it, and check its page.
# Usage: scripts/smoke.sh <roost-playground command> [port]
set -euo pipefail
command="$1"
port="${2:-4599}"
work="$(mktemp -d)"
cd "$work"
"$command" new Smoke.swift --no-open --port "$port" > runner.log 2>&1 &
runner=$!
trap 'kill -INT "$runner" 2>/dev/null; wait "$runner" 2>/dev/null || true' EXIT
status() { curl -s -H "Host: 127.0.0.1:$port" "http://127.0.0.1:$port/__playground/status" || true; }
field() { python3 -c "import json,sys; print(json.load(sys.stdin).get('$1') or '')" 2>/dev/null || true; }
deadline=$((SECONDS + 1200))
until [[ "$(status | field phase)" =~ ^(ready|failed)$ ]]; do
    if ! kill -0 "$runner" 2>/dev/null; then cat runner.log; echo "The runner exited." >&2; exit 1; fi
    if (( SECONDS > deadline )); then cat runner.log; echo "Timed out waiting for the first build." >&2; exit 1; fi
    sleep 2
done
if [[ "$(status | field phase)" != ready ]]; then status | field diagnostics; exit 1; fi
page="$(curl -s "$(status | field previewURL)")"
grep -q "Hello, Roost." <<< "$page" || { echo "$page"; echo "The starter page did not render." >&2; exit 1; }
echo "Starter built and rendered in $(status | field buildMilliseconds) ms."

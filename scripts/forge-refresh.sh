#!/usr/bin/env bash
# forge-refresh.sh — Keep Forge OF snapshot fresh
# Called by cron every 4 hours. Safe, idempotent, read-only.
#
# Updates: .cache/omnifocus-snapshot.json
# No Forge.app GUI required — the CLI binary is self-contained.

set -euo pipefail

forge_dir="${FORGE_DIR:-$HOME/Documents/Forge}"
cache_dir="$forge_dir/.cache"
log="$cache_dir/forge-refresh.log"

if [[ -n "${FORGE_BIN:-}" ]]; then
  forge_bin="$FORGE_BIN"
elif command -v forge >/dev/null 2>&1; then
  forge_bin="$(command -v forge)"
elif [[ -x "$HOME/bin/forge" ]]; then
  forge_bin="$HOME/bin/forge"
else
  echo "forge not found on PATH or at \$HOME/bin/forge" >&2
  exit 1
fi

mkdir -p "$cache_dir"

timestamp=$(date '+%Y-%m-%d %H:%M:%S')

# Run forge omnifocus refresh (writes snapshot, lists task counts)
echo "--- $timestamp ---" >> "$log"
"$forge_bin" omnifocus refresh 2>&1 | tee -a "$log" || {
    echo "FAILED at $timestamp" >> "$log"
    exit 1
}
echo "" >> "$log"

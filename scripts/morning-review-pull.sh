#!/usr/bin/env bash
# morning-review-pull.sh — read-only morning data pulls (sync + brief bundle)
#
# Phase 1: OmniFocus refresh (kanban join). Legacy OF→TASKS.toml sync only when
# Super Productivity is not the enabled task store.
# Phase 2: forge-brief.py (calendar + board + inbox/dues from SP when enabled)
#
# GitHub owned/fork checks stay with the synthesising agent (see morning-brief.mdc).

set -euo pipefail

forge_dir="${FORGE_DIR:-$HOME/Documents/Software/Forge}"
cache_dir="$forge_dir/.cache/morning-review"

if [[ -n "${FORGE_BIN:-}" ]]; then
  forge_bin="$FORGE_BIN"
elif command -v forge >/dev/null 2>&1; then
  forge_bin="$(command -v forge)"
elif [[ -x "$HOME/bin/forge" ]]; then
  forge_bin="$HOME/bin/forge"
else
  echo "forge not found; set FORGE_BIN or install the CLI" >&2
  exit 1
fi

mkdir -p "$cache_dir"
cd "$forge_dir"

stamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "[$stamp] morning-review-pull: OF refresh"
"$forge_bin" omnifocus refresh --apply-finder | tee "$cache_dir/of-refresh.txt"

sp_enabled="$(
  python3 - <<'PY'
from pathlib import Path
import sys
sys.path.insert(0, "scripts")
from forge_tasks_world.superproductivity import config_from_file
print("1" if config_from_file(Path("config.yaml")).enabled else "0")
PY
)"

if [[ "$sp_enabled" == "1" ]]; then
  echo "[$stamp] morning-review-pull: skip OF→TASKS (Super Productivity is task store)" | tee "$cache_dir/sync-tasks.txt"
else
  echo "[$stamp] morning-review-pull: project tasks sync"
  python3 scripts/sync-of-tasks-from-of.py | tee "$cache_dir/sync-tasks.txt"
fi

echo "[$stamp] morning-review-pull: forge-brief (calendar + board + due)"
python3 scripts/forge-brief.py --calendar-days 1 | tee "$cache_dir/forge-brief.txt"

echo "[$stamp] morning-review-pull: done"
echo "  brief: $cache_dir/forge-brief.txt"

#!/usr/bin/env bash
# reminders-capture-drain.sh — drain Apple Reminders Inbox into Super Productivity
#
# Reads incomplete reminders from a Reminders list (default: Inbox), captures each
# into the SP inbox via `forge capture --source reminders`, then marks the
# reminder completed. Durable receipts prevent recapture after partial failure.
#
# Usage:
#   bash scripts/reminders-capture-drain.sh
#   bash scripts/reminders-capture-drain.sh --dry-run
#   bash scripts/reminders-capture-drain.sh --list Inbox --no-complete
#
# Shortcuts: Run Shell Script → this file (absolute path). stdout is JSON.

set -euo pipefail

list_name="Inbox"
dry_run=0
do_complete=1
forge_dir="${FORGE_DIR:-$HOME/Documents/Software/Forge}"
forge_bin="${FORGE_BIN:-}"

usage() {
  cat <<'EOF'
Usage: reminders-capture-drain.sh [options]

Drain incomplete Apple Reminders from a list into Super Productivity's inbox
via `forge capture` (requires SP Local REST running and a configured token).

Options:
  --list NAME       Reminders list title (default: Inbox)
  --dry-run         List candidates only; do not capture or complete
  --no-complete     Capture but leave reminders incomplete (receipts prevent recapture)
  --forge-home DIR  Forge home (default: FORGE_DIR or ~/Documents/Software/Forge)
  --forge PATH      forge binary (default: FORGE_BIN, then PATH, then ~/bin/forge)
  -h, --help        Show this help

Stdout: JSON summary. Diagnostics go to stderr.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list)
      list_name="${2:?--list requires a name}"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --no-complete)
      do_complete=0
      shift
      ;;
    --forge-home)
      forge_dir="${2:?--forge-home requires a path}"
      shift 2
      ;;
    --forge)
      forge_bin="${2:?--forge requires a path}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$forge_bin" ]]; then
  if command -v forge >/dev/null 2>&1; then
    forge_bin="$(command -v forge)"
  elif [[ -x "$HOME/bin/forge" ]]; then
    forge_bin="$HOME/bin/forge"
  else
    echo "forge not found; set --forge or FORGE_BIN" >&2
    exit 1
  fi
fi

forge_dir="$(cd "$forge_dir" && pwd)"

export DRAIN_LIST="$list_name"
export DRAIN_DRY_RUN="$dry_run"
export DRAIN_DO_COMPLETE="$do_complete"
export DRAIN_FORGE_BIN="$forge_bin"
export DRAIN_FORGE_DIR="$forge_dir"

python3 "$(dirname "$0")/reminders_capture_drain.py"

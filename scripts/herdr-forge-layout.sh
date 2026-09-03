#!/usr/bin/env bash
# herdr-forge-layout.sh — apply a Forge workspace Herdr layout preset
#
# Presets (first argument):
#   brief      — 50/50 orchestrator | morning brief (default today)
#   dashboard  — 65/35 main | live dashboard watch (split layout, 60s)
#   triple     — left main, right top brief, right bottom tick strip
#   stack      — main over full dashboard (compact)
#
# Requires HERDR_ENV=1 and cwd in Forge (or FORGE_DIR set).

set -euo pipefail

if [[ "${HERDR_ENV:-}" != "1" ]]; then
  echo "Run inside a Herdr-managed pane (HERDR_ENV=1)." >&2
  exit 1
fi

preset="${1:-brief}"
forge_dir="${FORGE_DIR:-$HOME/Documents/Software/Forge}"
dash="$forge_dir/scripts/forge-dashboard.py"

case "$preset" in
  brief)
    echo "[herdr-forge] layout brief: ensure right pane for Morning Brief worker"
    if herdr pane list 2>/dev/null | rg -q 'w8:p4' 2>/dev/null; then
      echo "  w8:p4 already present — use Morning Brief pane for brief worker"
    else
      result="$(herdr pane split --current --direction right --cwd "$forge_dir" --no-focus)"
      pane_id="$(printf '%s' "$result" | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['pane']['pane_id'])")"
      echo "  split right → $pane_id (start Cursor agent there for briefs)"
    fi
    ;;

  dashboard)
    echo "[herdr-forge] layout dashboard: right pane live watch"
    result="$(herdr pane split --current --direction right --ratio 0.65 --cwd "$forge_dir" --no-focus)"
    pane_id="$(printf '%s' "$result" | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['pane']['pane_id'])")"
    herdr pane run "$pane_id" "python3 '$dash' --layout split --watch 60"
    echo "  dashboard watch on $pane_id (split layout, 60s refresh)"
    ;;

  triple)
    echo "[herdr-forge] layout triple: right split brief + tick"
    result="$(herdr pane split --current --direction right --ratio 0.6 --cwd "$forge_dir" --no-focus)"
    right_pane="$(printf '%s' "$result" | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['pane']['pane_id'])")"
    result2="$(herdr pane split --pane "$right_pane" --direction down --ratio 0.75 --cwd "$forge_dir" --no-focus)"
    brief_pane="$(printf '%s' "$result2" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result']['pane']['pane_id'])")"
    tick_pane="$(herdr pane list 2>/dev/null | python3 -c "
import json,sys
panes=json.load(sys.stdin)['result']['panes']
ids=[p['pane_id'] for p in panes if p.get('workspace_id')=='w8']
print([i for i in ids if i not in {'w8:p1','$right_pane'}][-1] if len(ids)>2 else '')
" 2>/dev/null || true)"
    if [[ -n "${tick_pane:-}" ]]; then
      herdr pane run "$tick_pane" "python3 '$dash' --layout tick --watch 30"
    fi
    echo "  brief pane: $brief_pane"
    echo "  tick pane:  ${tick_pane:-unknown}"
    ;;

  stack)
    echo "[herdr-forge] layout stack: bottom compact dashboard"
    result="$(herdr pane split --current --direction down --ratio 0.72 --cwd "$forge_dir" --no-focus)"
    pane_id="$(printf '%s' "$result" | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['pane']['pane_id'])")"
    herdr pane run "$pane_id" "python3 '$dash' --layout compact --watch 90"
    echo "  compact dashboard on $pane_id (90s refresh)"
    ;;

  *)
    echo "Unknown preset: $preset" >&2
    echo "Use: brief | dashboard | triple | stack" >&2
    exit 1
    ;;
esac

echo "[herdr-forge] current layout:"
herdr pane layout --pane "${HERDR_PANE_ID:-}" 2>/dev/null || herdr pane list

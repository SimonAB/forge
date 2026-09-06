#!/usr/bin/env python3
"""Focus a Super Productivity project in the UI (router hash + optional NgRx).

SP's ``superproductivity://`` scheme cannot open an existing project. This helper
uses Chrome DevTools Protocol to set ``#/project/<id>/tasks``. If CDP is not
already available it briefly relaunches SP with ``--remote-debugging-port=9222``.

Usage::

    python3 scripts/forge-sp-focus-project.py <projectId>
"""

from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path

from forge_tasks_world.sp_cdp import ensure_cdp

FOCUS_REQUEST = (
    Path.home()
    / "Library/Application Support/superProductivity/forge-focus-request.json"
)


def write_focus_request(project_id: str) -> None:
    """Persist the focus request for optional SP plugins / debugging."""
    FOCUS_REQUEST.parent.mkdir(parents=True, exist_ok=True)
    FOCUS_REQUEST.write_text(
        json.dumps(
            {
                "projectId": project_id,
                "ts": int(time.time() * 1000),
            }
        ),
        encoding="utf-8",
    )

def websocket_module():
    """Check dependencies before asking the app to quit."""
    try:
        import websocket
    except ImportError as exc:
        raise SystemExit(
            "websocket-client required. Example:\n"
            "  python3 -m venv .venv && "
            ".venv/bin/python -m pip install -r scripts/requirements.txt\n"
            "  .venv/bin/python scripts/forge-sp-focus-project.py <id>"
        ) from exc
    return websocket


def navigate(ws_url: str, project_id: str) -> dict:
    """Set the Angular hash route (and dispatch work-context) via CDP."""
    websocket = websocket_module()

    ws = websocket.create_connection(ws_url, timeout=20, suppress_origin=True)
    n = 0

    def call(method: str, params: dict | None = None) -> dict:
        nonlocal n
        n += 1
        msg_id = n
        ws.send(json.dumps({"id": msg_id, "method": method, "params": params or {}}))
        while True:
            data = json.loads(ws.recv())
            if data.get("id") == msg_id:
                return data

    call("Runtime.enable")
    # Wait for the SPA shell
    call(
        "Runtime.evaluate",
        {
            "expression": """(async () => {
              for (let i = 0; i < 50; i++) {
                if (document.querySelector('app-root') && (document.body.innerText||'').length > 20)
                  return true;
                await new Promise((r) => setTimeout(r, 200));
              }
              return false;
            })()""",
            "awaitPromise": True,
            "returnByValue": True,
        },
    )

    # Escape for JS string
    pid = json.dumps(project_id)
    expr = f"""
(async () => {{
  const id = {pid};
  const hash = '#/project/' + id + '/tasks';
  // Prefer Angular-friendly hash navigation
  if (location.hash !== hash) {{
    location.hash = hash;
  }} else {{
    // Force a reload of the same hash
    location.hash = '#/tag/TODAY/tasks';
    await new Promise((r) => setTimeout(r, 50));
    location.hash = hash;
  }}
  // Also set work context when PluginAPI is available in page (usually not)
  try {{
    if (window.PluginAPI && typeof window.PluginAPI.dispatchAction === 'function') {{
      window.PluginAPI.dispatchAction({{
        type: '[WorkContext] Set Active Work Context',
        activeId: id,
        activeType: 'PROJECT',
      }});
    }}
  }} catch (e) {{}}
  await new Promise((r) => setTimeout(r, 300));
  return {{ hash: location.hash, href: location.href }};
}})()
"""
    result = call(
        "Runtime.evaluate",
        {"expression": expr, "awaitPromise": True, "returnByValue": True},
    )
    ws.close()
    return result.get("result", {}).get("result", {})


def main(argv: list[str]) -> int:
    """Focus the given Super Productivity project id."""
    if len(argv) < 2 or not argv[1].strip():
        print("usage: forge-sp-focus-project.py <projectId>", file=sys.stderr)
        return 2
    project_id = argv[1].strip()
    websocket_module()
    write_focus_request(project_id)
    ws_url = ensure_cdp()
    outcome = navigate(ws_url, project_id)
    # Bring SP to the front after navigating (CDP alone leaves Forge/Finder focused).
    subprocess.run(
        ["/usr/bin/open", "-a", "Super Productivity"],
        check=False,
        capture_output=True,
    )
    print(json.dumps({"ok": True, "projectId": project_id, "nav": outcome}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

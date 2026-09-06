#!/usr/bin/env python3
"""Mirror Finder project folder paths into Super Productivity's sidebar tree.

SP stores hierarchy in ``menuTree.projectTree`` (folders ``k:"f"``, projects
``k:"p"``). Local REST and Plugin ``dispatchAction`` cannot update it. This
script builds the tree from ``forge board --json`` paths under ``--docs-root``
(default ``~/Documents``), writes ``SUP_OPS`` ``state_cache`` via Chrome
DevTools Protocol, and reloads the app.

Usage::

    python3 scripts/forge-sp-menu-tree.py --forge-home . --dry-run
    python3 scripts/forge-sp-menu-tree.py --forge-home .
    # or: forge superproductivity mirror-menu-tree

Requires ``websocket-client`` and briefly relaunches Super Productivity with
``--remote-debugging-port=9222`` when CDP is not already open.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
import urllib.request
import uuid
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_SP_BIN = "/Applications/Super Productivity.app/Contents/MacOS/Super Productivity"


def folder_id(name: str) -> str:
    """Stable forge-prefixed folder id derived from the path key."""
    return "forge-folder-" + uuid.uuid5(uuid.NAMESPACE_URL, f"forge-sp-folder:{name}").hex[:20]


def _sp_projects(forge_home: Path) -> list[dict]:
    """List Super Productivity projects via the Forge SP adapter."""
    raw = subprocess.check_output(
        [
            sys.executable,
            str(SCRIPT_DIR / "forge-superproductivity.py"),
            "--forge-home",
            str(forge_home),
            "--json",
            "list",
        ],
        text=True,
    )
    return json.loads(raw)


def build_project_tree(
    forge_home: Path,
    docs_root: Path,
) -> tuple[list, dict]:
    """Build SP ``projectTree`` from board folder paths + SP project titles."""
    board = json.loads(subprocess.check_output(["forge", "board", "--json"], text=True))
    projects = board.get("projects") or []
    sp = _sp_projects(forge_home)
    sp_id = {
        p.get("title"): p.get("id")
        for p in sp
        if p.get("title") and p.get("title") != "Inbox"
    }

    root: dict = {"folders": {}, "projects": []}
    mapped = 0
    missing_sp: list[str] = []
    for proj in projects:
        name = proj["name"]
        path = Path(proj["path"])
        pid = sp_id.get(name)
        if not pid:
            missing_sp.append(name)
            continue
        try:
            parts = list(path.relative_to(docs_root).parts[:-1])
        except ValueError:
            parts = ["Misc"]
        node = root
        for part in parts:
            node = node["folders"].setdefault(part, {"folders": {}, "projects": []})
        node["projects"].append({"k": "p", "id": pid})
        mapped += 1

    def to_tree(node: dict, path_prefix: str = "") -> list:
        out: list = []
        for fname in sorted(node["folders"]):
            child = node["folders"][fname]
            folder_path = f"{path_prefix}/{fname}" if path_prefix else fname
            out.append(
                {
                    "k": "f",
                    "id": folder_id(folder_path),
                    "name": fname,
                    "isExpanded": True,
                    "children": to_tree(child, folder_path),
                }
            )
        out.extend(sorted(node["projects"], key=lambda n: n["id"]))
        return out

    project_tree = to_tree(root)
    board_titles = {p["name"] for p in projects}
    extras = [
        {"k": "p", "id": pid}
        for title, pid in sorted(sp_id.items())
        if title not in board_titles
    ]
    project_tree.extend(extras)
    meta = {
        "mapped_board_projects": mapped,
        "missing_sp": missing_sp,
        "sp_only_extras": len(extras),
        "docs_root": str(docs_root),
    }
    return project_tree, meta


def summarize(nodes: list, depth: int = 0) -> None:
    """Print a compact folder outline."""
    for n in nodes:
        if n.get("k") == "f":
            print("  " * depth + f"[F] {n['name']} ({len(n.get('children') or [])})")
            summarize(n.get("children") or [], depth + 1)


def ensure_cdp(sp_bin: str) -> None:
    """Quit SP if needed and launch with remote debugging on port 9222."""
    try:
        urllib.request.urlopen("http://127.0.0.1:9222/json/version", timeout=1)
        return
    except Exception:
        pass
    subprocess.run(
        ["osascript", "-e", 'tell application "Super Productivity" to quit'],
        check=False,
    )
    time.sleep(2)
    subprocess.run(["pkill", "-9", "-f", "Super Productivity"], check=False)
    time.sleep(1)
    subprocess.Popen(
        [sp_bin, "--remote-debugging-port=9222", "--remote-allow-origins=*"],
        stdout=open("/tmp/sp-cdp.log", "w"),
        stderr=subprocess.STDOUT,
    )


def wait_cdp(timeout: float = 40.0) -> str:
    """Return the page websocket debugger URL once CDP and REST are up."""
    deadline = time.time() + timeout
    last_err: Exception | None = None
    while time.time() < deadline:
        try:
            pages = json.load(
                urllib.request.urlopen("http://127.0.0.1:9222/json/list", timeout=2)
            )
            page = next(p for p in pages if p.get("type") == "page")
            health = json.load(
                urllib.request.urlopen("http://127.0.0.1:3876/health", timeout=2)
            )
            if health.get("ok"):
                return page["webSocketDebuggerUrl"]
        except Exception as exc:  # noqa: BLE001
            last_err = exc
            time.sleep(0.4)
    raise SystemExit(f"CDP not ready: {last_err}")


def apply_via_indexeddb(tree: list, sp_bin: str) -> dict:
    """Write ``menuTree.projectTree`` into SUP_OPS state_cache and reload."""
    try:
        import websocket
    except ImportError as exc:
        raise SystemExit(
            "websocket-client required. Example:\n"
            "  python3 -m venv /tmp/sp-cdp-venv && "
            "/tmp/sp-cdp-venv/bin/pip install websocket-client\n"
            "  /tmp/sp-cdp-venv/bin/python scripts/forge-sp-menu-tree.py --forge-home ."
        ) from exc

    ensure_cdp(sp_bin)
    ws_url = wait_cdp()
    ws = websocket.create_connection(ws_url, timeout=60)
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
    call(
        "Runtime.evaluate",
        {
            "expression": """(async () => {
              for (let i = 0; i < 40; i++) {
                if (document.querySelector('app-root') && document.body.innerText.length > 50)
                  return true;
                await new Promise((r) => setTimeout(r, 250));
              }
              return false;
            })()""",
            "awaitPromise": True,
            "returnByValue": True,
        },
    )
    call(
        "Runtime.evaluate",
        {
            "expression": "window.__FORGE_TREE__ = " + json.dumps(tree),
            "returnByValue": True,
        },
    )
    write = call(
        "Runtime.evaluate",
        {
            "expression": """(async () => {
              const tree = window.__FORGE_TREE__;
              const db = await new Promise((res, rej) => {
                const r = indexedDB.open('SUP_OPS');
                r.onsuccess = () => res(r.result);
                r.onerror = () => rej(r.error);
              });
              const tx = db.transaction('state_cache', 'readwrite');
              const store = tx.objectStore('state_cache');
              const current = await new Promise((res, rej) => {
                const r = store.get('current');
                r.onsuccess = () => res(r.result);
                r.onerror = () => rej(r.error);
              });
              if (!current || !current.state) throw new Error('no current state');
              const before = ((current.state.menuTree || {}).projectTree || [])
                .map((n) => (n.k === 'f' ? 'F:' + n.name : 'P'))
                .slice(0, 20);
              current.state.menuTree = current.state.menuTree || { tagTree: [] };
              current.state.menuTree.projectTree = tree;
              await new Promise((res, rej) => {
                const r = store.put(current);
                r.onsuccess = () => res();
                r.onerror = () => rej(r.error);
              });
              await new Promise((res, rej) => {
                tx.oncomplete = () => res();
                tx.onerror = () => rej(tx.error);
              });
              db.close();
              return {
                ok: true,
                before,
                afterFolders: tree.filter((n) => n.k === 'f').map((n) => n.name),
              };
            })()""",
            "returnByValue": True,
            "awaitPromise": True,
        },
    )
    result = write.get("result", {}).get("result", {})
    if write.get("result", {}).get("exceptionDetails"):
        raise SystemExit(write["result"]["exceptionDetails"])
    call("Page.enable")
    call("Page.reload", {})
    ws.close()
    return result.get("value") if isinstance(result, dict) and "value" in result else result


def main(argv: list[str] | None = None) -> int:
    """Build Finder-mirrored tree and optionally apply it via CDP."""
    parser = argparse.ArgumentParser(
        description="Mirror Finder project paths into Super Productivity folders"
    )
    parser.add_argument(
        "--forge-home",
        default=".",
        help="Forge home (config.yaml + scripts); default: current directory",
    )
    parser.add_argument(
        "--docs-root",
        type=Path,
        default=Path.home() / "Documents",
        help="Path root used to derive folder nesting (default: ~/Documents)",
    )
    parser.add_argument(
        "--sp-bin",
        default=DEFAULT_SP_BIN,
        help="Super Productivity binary path",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the planned tree only; do not relaunch SP or write state",
    )
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON")
    args = parser.parse_args(argv)

    forge_home = Path(args.forge_home).expanduser().resolve()
    docs_root = args.docs_root.expanduser().resolve()
    tree, meta = build_project_tree(forge_home, docs_root)

    if args.dry_run:
        if args.json:
            print(json.dumps({"meta": meta, "projectTree": tree}, indent=2))
        else:
            print(json.dumps(meta, indent=2))
            summarize(tree)
            print("Dry run only; no changes applied.")
        return 0

    if args.json:
        print(json.dumps({"meta": meta, "projectTree_preview": True}, indent=2))
    else:
        print(json.dumps(meta, indent=2))
        summarize(tree)

    applied = apply_via_indexeddb(tree, args.sp_bin)
    if args.json:
        print(json.dumps({"applied": applied}, indent=2))
    else:
        print(json.dumps({"applied": applied}, indent=2))
        print(
            "Applied. Quit Super Productivity and reopen normally "
            "(without --remote-debugging-port) for daily use."
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Attach Super Productivity repeat configs from OmniFocus RRULEs (CDP).

Local REST cannot create recurrence. This script writes ``taskRepeatCfg`` into
SP's IndexedDB ``state_cache`` (same technique as ``forge-sp-menu-tree.py``)
and sets ``repeatCfgId`` on the matching imported tasks (``[forge:of-id:…]``).

Default is dry-run. Use ``--apply`` after reviewing the plan.

Requires ``websocket-client`` and may briefly relaunch Super Productivity with
``--remote-debugging-port=9222``.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
import time
import urllib.request
import uuid
from collections import defaultdict
from dataclasses import asdict, dataclass
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from forge_tasks_world.superproductivity import (  # noqa: E402
    INBOX_PROJECT_ID,
    open_client,
)
from forge_tasks_world.sp_cdp import SP_BIN, ensure_cdp  # noqa: E402

OF_ID_RE = re.compile(r"\[forge:of-id:([^\]]+)\]")
OF_RRULE_NOTE_RE = re.compile(r"\[forge:of-rrule:([^\]]+)\]")
BYDAY_MAP = {
    "SU": "sunday",
    "MO": "monday",
    "TU": "tuesday",
    "WE": "wednesday",
    "TH": "thursday",
    "FR": "friday",
    "SA": "saturday",
}
WEEKDAY_INDEX = {
    "SU": 0,
    "MO": 1,
    "TU": 2,
    "WE": 3,
    "TH": 4,
    "FR": 5,
    "SA": 6,
}


def _load_sync_of() -> Any:
    """Load hyphenated OmniFocus export helpers."""
    path = SCRIPT_DIR / "sync-of-tasks-from-of.py"
    spec = importlib.util.spec_from_file_location("sync_of_tasks_from_of", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_sync_of = _load_sync_of()
resolve_forge_home = _sync_of.resolve_forge_home


OMNIJS_RECURRING = r"""
function() {
  function iso(d) {
    if (!d) return null;
    try { return d.toISOString(); } catch (e) { return null; }
  }
  var rows = [];
  var all = flattenedTasks || [];
  for (var i = 0; i < all.length; i++) {
    var t = all[i];
    if (t.completed) continue;
    var r = null;
    try { r = t.repetitionRule; } catch (e) { r = null; }
    if (!r) continue;
    var ruleString = null;
    try { ruleString = r.ruleString; } catch (e) {}
    if (!ruleString) continue;
    var proj = null;
    try { proj = t.containingProject ? t.containingProject.name : null; } catch (e) {}
    rows.push({
      id: t.id.primaryKey,
      name: t.name,
      due: iso(t.dueDate),
      defer: iso(t.deferDate),
      planned: iso(t.plannedDate),
      ofProjectName: proj,
      ruleString: ruleString
    });
  }
  return JSON.stringify({count: rows.length, tasks: rows});
}
"""


@dataclass
class PlannedRepeat:
    """One OmniFocus series mapped onto an SP task + repeat config."""

    of_id: str
    title: str
    of_project: str | None
    rule_string: str
    sp_task_id: str | None
    sp_project_id: str | None
    action: str
    reason: str | None
    cfg: dict[str, Any] | None
    warnings: list[str]


def export_recurring_omnifocus() -> dict[str, Any]:
    """Return pending OmniFocus tasks that carry a repetition rule."""
    import subprocess
    import tempfile

    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False) as handle:
        handle.write(OMNIJS_RECURRING.strip())
        js_path = handle.name
    script = f"""
ObjC.import("Foundation");
const read = (path) => ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null));
Application("OmniFocus").evaluateJavascript("(" + read("{js_path}") + ")()");
"""
    raw = subprocess.check_output(["osascript", "-l", "JavaScript"], input=script, text=True)
    return json.loads(raw)


def parse_rrule(rule: str) -> dict[str, str]:
    """Parse a simple RRULE string into a key/value map."""
    out: dict[str, str] = {}
    text = rule.strip()
    if text.upper().startswith("RRULE:"):
        text = text[6:]
    for part in text.split(";"):
        if "=" not in part:
            continue
        key, value = part.split("=", 1)
        out[key.strip().upper()] = value.strip()
    return out


def _iso_day(value: str | None) -> str | None:
    """Return YYYY-MM-DD from an ISO timestamp."""
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).date().isoformat()
    except ValueError:
        return value[:10] if len(value) >= 10 else None


def _weekday_from_iso(value: str | None) -> str | None:
    """Return SP weekday key from an ISO timestamp."""
    if not value:
        return None
    try:
        instant = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return [
        "monday",
        "tuesday",
        "wednesday",
        "thursday",
        "friday",
        "saturday",
        "sunday",
    ][instant.weekday()]


def map_rrule_to_cfg(
    *,
    rule_string: str,
    title: str,
    project_id: str | None,
    due: str | None,
    defer: str | None,
    of_id: str,
) -> tuple[dict[str, Any], list[str]]:
    """Map an OmniFocus RRULE onto an SP TaskRepeatCfg payload."""
    warnings: list[str] = []
    parts = parse_rrule(rule_string)
    freq = (parts.get("FREQ") or "WEEKLY").upper()
    interval = int(parts.get("INTERVAL") or "1")
    start = _iso_day(due) or _iso_day(defer) or date.today().isoformat()

    cfg: dict[str, Any] = {
        "id": "forge-rpt-" + uuid.uuid5(uuid.NAMESPACE_URL, f"of-rrule:{of_id}").hex[:16],
        "projectId": project_id,
        "title": title,
        "tagIds": [],
        "order": 0,
        "isPaused": False,
        "quickSetting": "CUSTOM",
        "repeatCycle": "WEEKLY",
        "repeatEvery": max(1, interval),
        "startDate": start,
        "monday": False,
        "tuesday": False,
        "wednesday": False,
        "thursday": False,
        "friday": False,
        "saturday": False,
        "sunday": False,
        "notes": f"[forge:source:omnifocus]\n[forge:of-id:{of_id}]\n[forge:of-rrule:{rule_string}]",
        "repeatFromCompletionDate": False,
        "waitForCompletion": False,
        "shouldInheritSubtasks": False,
        "disableAutoUpdateSubtasks": False,
        "skipOverdue": False,
        "lastTaskCreationDay": start,
        "lastTaskCreation": int(datetime.now(tz=timezone.utc).timestamp() * 1000),
    }

    if freq == "DAILY":
        cfg["repeatCycle"] = "DAILY"
        cfg["quickSetting"] = "DAILY" if interval == 1 else "CUSTOM"
        for day in ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"):
            cfg[day] = True
    elif freq == "WEEKLY":
        cfg["repeatCycle"] = "WEEKLY"
        byday = parts.get("BYDAY")
        if byday:
            for token in byday.split(","):
                token = token.strip().upper()
                # Strip ordinal prefixes: 1MO, -1SU → MO / SU
                core = re.sub(r"^-?\d+", "", token)
                key = BYDAY_MAP.get(core)
                if key:
                    cfg[key] = True
                else:
                    warnings.append(f"unrecognised BYDAY token {token}")
            if sum(1 for d in BYDAY_MAP.values() if cfg[d]) == 1 and interval == 1:
                cfg["quickSetting"] = "WEEKLY_CURRENT_WEEKDAY"
        else:
            weekday = _weekday_from_iso(due) or _weekday_from_iso(defer) or "monday"
            cfg[weekday] = True
            cfg["quickSetting"] = "WEEKLY_CURRENT_WEEKDAY"
            warnings.append(f"no BYDAY; anchored to {weekday}")
    elif freq == "MONTHLY":
        cfg["repeatCycle"] = "MONTHLY"
        byday = parts.get("BYDAY")
        bymonthday = parts.get("BYMONTHDAY")
        if byday:
            token = byday.split(",")[0].strip().upper()
            ordinal_match = re.match(r"^(-?\d+)(SU|MO|TU|WE|TH|FR|SA)$", token)
            if ordinal_match:
                ordinal = int(ordinal_match.group(1))
                weekday = ordinal_match.group(2)
                if ordinal in (1, 2, 3, 4, -1):
                    cfg["monthlyWeekOfMonth"] = ordinal
                    cfg["monthlyWeekday"] = WEEKDAY_INDEX[weekday]
                    cfg["quickSetting"] = "MONTHLY_NTH_WEEKDAY"
                else:
                    warnings.append(f"unsupported monthly ordinal {ordinal}; using CUSTOM")
                    cfg["quickSetting"] = "CUSTOM"
            else:
                warnings.append(f"complex monthly BYDAY {byday}; using startDate day")
                cfg["quickSetting"] = "MONTHLY_CURRENT_DATE"
        elif bymonthday == "-1":
            cfg["monthlyLastDay"] = True
            cfg["quickSetting"] = "MONTHLY_LAST_DAY"
        elif bymonthday:
            day_num = int(bymonthday.split(",")[0])
            # Anchor startDate to that day-of-month in the current/start month.
            try:
                y, m, _ = start.split("-")
                cfg["startDate"] = f"{y}-{m}-{day_num:02d}"
            except ValueError:
                warnings.append(f"could not apply BYMONTHDAY={bymonthday}")
            cfg["quickSetting"] = "MONTHLY_CURRENT_DATE"
        else:
            cfg["quickSetting"] = "MONTHLY_CURRENT_DATE"
    elif freq == "YEARLY":
        cfg["repeatCycle"] = "YEARLY"
        cfg["quickSetting"] = "YEARLY_CURRENT_DATE"
    else:
        warnings.append(f"unsupported FREQ={freq}; defaulting to WEEKLY")
        cfg["repeatCycle"] = "WEEKLY"
        weekday = _weekday_from_iso(due) or "monday"
        cfg[weekday] = True

    if parts.get("COUNT") or parts.get("UNTIL"):
        warnings.append("COUNT/UNTIL not represented in SP repeat config")
    return cfg, warnings


def index_sp_by_of_id(client: Any) -> dict[str, dict[str, Any]]:
    """Map OmniFocus ids from SP task notes onto SP task records."""
    by_of: dict[str, dict[str, Any]] = {}
    project_ids = [p["id"] for p in client.projects()] + [INBOX_PROJECT_ID]
    for project_id in dict.fromkeys(project_ids):
        try:
            tasks = client.tasks(project_id, include_done=True)
        except Exception:  # noqa: BLE001
            continue
        for task in tasks:
            notes = str(task.get("notes") or "")
            match = OF_ID_RE.search(notes)
            if not match:
                continue
            by_of[match.group(1)] = task
    return by_of


def dedupe_series(tasks: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Collapse OF instance copies that share title+project+rule."""
    groups: dict[tuple[str, str, str], list[dict[str, Any]]] = defaultdict(list)
    for task in tasks:
        key = (
            (task.get("name") or "").strip(),
            (task.get("ofProjectName") or "").strip(),
            (task.get("ruleString") or "").strip(),
        )
        groups[key].append(task)

    chosen: list[dict[str, Any]] = []
    for series in groups.values():
        def sort_key(item: dict[str, Any]) -> tuple[str, str]:
            return (item.get("due") or "9999", item.get("id") or "")

        series_sorted = sorted(series, key=sort_key)
        # Prefer the soonest dated instance; fall back to first id.
        pick = series_sorted[0]
        pick = dict(pick)
        pick["_series_count"] = len(series)
        pick["_series_ids"] = [t["id"] for t in series]
        chosen.append(pick)
    return chosen


def plan_repeats(
    of_tasks: list[dict[str, Any]],
    sp_by_of: dict[str, dict[str, Any]],
) -> list[PlannedRepeat]:
    """Build attach/skip plan for each OF recurring series."""
    rows: list[PlannedRepeat] = []
    for task in dedupe_series(of_tasks):
        of_id = str(task["id"])
        title = (task.get("name") or "").strip()
        rule = (task.get("ruleString") or "").strip()
        sp = sp_by_of.get(of_id)
        # If primary instance missing, try other series members.
        if sp is None:
            for alt in task.get("_series_ids") or []:
                sp = sp_by_of.get(alt)
                if sp is not None:
                    of_id = alt
                    break
        if sp is None:
            rows.append(
                PlannedRepeat(
                    of_id=of_id,
                    title=title,
                    of_project=task.get("ofProjectName"),
                    rule_string=rule,
                    sp_task_id=None,
                    sp_project_id=None,
                    action="skip",
                    reason="no matching SP task ([forge:of-id] missing)",
                    cfg=None,
                    warnings=[],
                )
            )
            continue

        if sp.get("repeatCfgId"):
            rows.append(
                PlannedRepeat(
                    of_id=of_id,
                    title=title,
                    of_project=task.get("ofProjectName"),
                    rule_string=rule,
                    sp_task_id=str(sp["id"]),
                    sp_project_id=sp.get("projectId"),
                    action="skip",
                    reason=f"already has repeatCfgId={sp.get('repeatCfgId')}",
                    cfg=None,
                    warnings=[],
                )
            )
            continue

        cfg, warnings = map_rrule_to_cfg(
            rule_string=rule,
            title=title,
            project_id=sp.get("projectId"),
            due=task.get("due"),
            defer=task.get("defer"),
            of_id=of_id,
        )
        series_n = int(task.get("_series_count") or 1)
        if series_n > 1:
            warnings.append(
                f"collapsed {series_n} OF instances into one SP repeat config"
            )
        rows.append(
            PlannedRepeat(
                of_id=of_id,
                title=title,
                of_project=task.get("ofProjectName"),
                rule_string=rule,
                sp_task_id=str(sp["id"]),
                sp_project_id=sp.get("projectId"),
                action="attach",
                reason=None,
                cfg=cfg,
                warnings=warnings,
            )
        )
    return rows


def wait_cdp_ready(timeout: float = 40.0) -> str:
    """Return page websocket URL once CDP + REST health are up."""
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


def apply_via_cdp(
    rows: list[PlannedRepeat],
    *,
    sp_bin: str,
) -> dict[str, Any]:
    """Write taskRepeatCfg entities and link tasks via IndexedDB state_cache."""
    try:
        import websocket
    except ImportError as exc:
        raise SystemExit(
            "websocket-client required. Example:\n"
            "  python3 -m venv .venv && .venv/bin/pip install websocket-client\n"
            "  .venv/bin/python scripts/of-to-sp-repeats.py --apply"
        ) from exc

    ensure_cdp(sp_bin=sp_bin)
    ws_url = wait_cdp_ready()
    ws = websocket.create_connection(ws_url, timeout=60, suppress_origin=True)
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

    payload = {
        "cfgs": [row.cfg for row in rows if row.action == "attach" and row.cfg],
        "links": [
            {"taskId": row.sp_task_id, "repeatCfgId": row.cfg["id"]}
            for row in rows
            if row.action == "attach" and row.cfg and row.sp_task_id
        ],
    }

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
    # Wait until IndexedDB state_cache has hydrated the tasks we intend to link.
    wanted = [link["taskId"] for link in payload["links"]]
    call(
        "Runtime.evaluate",
        {
            "expression": "window.__FORGE_WANTED_TASKS__ = " + json.dumps(wanted),
            "returnByValue": True,
        },
    )
    ready = call(
        "Runtime.evaluate",
        {
            "expression": """(async () => {
              const wanted = window.__FORGE_WANTED_TASKS__ || [];
              for (let i = 0; i < 60; i++) {
                const db = await new Promise((res, rej) => {
                  const r = indexedDB.open('SUP_OPS');
                  r.onsuccess = () => res(r.result);
                  r.onerror = () => rej(r.error);
                });
                const tx = db.transaction('state_cache', 'readonly');
                const store = tx.objectStore('state_cache');
                const current = await new Promise((res, rej) => {
                  const r = store.get('current');
                  r.onsuccess = () => res(r.result);
                  r.onerror = () => rej(r.error);
                });
                db.close();
                const ents = (((current || {}).state || {}).task || {}).entities || {};
                const found = wanted.filter((id) => id in ents).length;
                if (wanted.length === 0 || found === wanted.length) {
                  return { ready: true, found, wanted: wanted.length, taskCount: Object.keys(ents).length };
                }
                await new Promise((r) => setTimeout(r, 500));
              }
              return { ready: false };
            })()""",
            "awaitPromise": True,
            "returnByValue": True,
        },
    )
    ready_val = ready.get("result", {}).get("result", {})
    if isinstance(ready_val, dict) and "value" in ready_val:
        ready_val = ready_val["value"]
    if not (isinstance(ready_val, dict) and ready_val.get("ready")):
        ws.close()
        raise SystemExit(f"state_cache tasks not hydrated: {ready_val}")

    call(
        "Runtime.evaluate",
        {
            "expression": "window.__FORGE_REPEATS__ = " + json.dumps(payload),
            "returnByValue": True,
        },
    )
    write = call(
        "Runtime.evaluate",
        {
            "expression": """(async () => {
              const payload = window.__FORGE_REPEATS__;
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
              const state = current.state;
              state.taskRepeatCfg = state.taskRepeatCfg || { ids: [], entities: {} };
              const ids = new Set(state.taskRepeatCfg.ids || []);
              const entities = state.taskRepeatCfg.entities || {};
              let created = 0;
              let updated = 0;
              for (const cfg of payload.cfgs) {
                if (entities[cfg.id]) updated += 1;
                else created += 1;
                entities[cfg.id] = cfg;
                ids.add(cfg.id);
              }
              state.taskRepeatCfg.ids = Array.from(ids);
              state.taskRepeatCfg.entities = entities;

              state.task = state.task || { ids: [], entities: {} };
              const tasks = state.task.entities || {};
              let linked = 0;
              let missingTasks = [];
              for (const link of payload.links) {
                const task = tasks[link.taskId];
                if (!task) {
                  missingTasks.push(link.taskId);
                  continue;
                }
                task.repeatCfgId = link.repeatCfgId;
                task.modified = Date.now();
                linked += 1;
              }
              state.task.entities = tasks;

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
              return { ok: true, created, updated, linked, missingTasks };
            })()""",
            "returnByValue": True,
            "awaitPromise": True,
        },
    )
    if write.get("result", {}).get("exceptionDetails"):
        ws.close()
        raise SystemExit(write["result"]["exceptionDetails"])
    result = write.get("result", {}).get("result", {})
    call("Page.enable")
    call("Page.reload", {})
    ws.close()
    return result.get("value") if isinstance(result, dict) and "value" in result else result


def print_human(rows: list[PlannedRepeat]) -> None:
    """Print a compact plan."""
    attach = [r for r in rows if r.action == "attach"]
    skip = [r for r in rows if r.action == "skip"]
    print("## OF → SP repeats plan")
    print(f"series: {len(rows)}  attach: {len(attach)}  skip: {len(skip)}")
    print("\nAttach:")
    for row in attach:
        warn = f"  warnings={row.warnings}" if row.warnings else ""
        cycle = (row.cfg or {}).get("repeatCycle")
        every = (row.cfg or {}).get("repeatEvery")
        print(f"  {cycle}×{every:g}  {row.rule_string:35}  {row.title[:50]}{warn}")
    if skip:
        print("\nSkip:")
        for row in skip:
            print(f"  {row.reason:40}  {row.title[:50]}")


def main() -> int:
    """CLI: dry-run plan or CDP apply."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--forge-home", type=Path, default=None)
    parser.add_argument("--apply", action="store_true", help="Write via CDP (not dry-run)")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--sp-bin", default=SP_BIN)
    args = parser.parse_args()

    forge_home = (args.forge_home or resolve_forge_home()).expanduser().resolve()
    print("Exporting OmniFocus recurring tasks…", file=sys.stderr)
    of_data = export_recurring_omnifocus()
    client = open_client(forge_home)
    print("Indexing SP imports…", file=sys.stderr)
    sp_by_of = index_sp_by_of_id(client)
    rows = plan_repeats(of_data.get("tasks") or [], sp_by_of)

    applied: dict[str, Any] | None = None
    if args.apply:
        attachable = [r for r in rows if r.action == "attach"]
        if not attachable:
            print("Nothing to attach.", file=sys.stderr)
        else:
            print(f"Applying {len(attachable)} repeat config(s) via CDP…", file=sys.stderr)
            applied = apply_via_cdp(attachable, sp_bin=args.sp_bin)
            print(json.dumps(applied, indent=2), file=sys.stderr)

    result = {
        "ok": True,
        "dry_run": not args.apply,
        "pending_of_recurring": of_data.get("count"),
        "series": len(rows),
        "attach": sum(1 for r in rows if r.action == "attach"),
        "skip": sum(1 for r in rows if r.action == "skip"),
        "applied": applied,
        "rows": [asdict(r) for r in rows],
    }
    if args.json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        print_human(rows)
        if not args.apply:
            print("\nDry-run only. Apply with:\n  python3 scripts/of-to-sp-repeats.py --apply")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

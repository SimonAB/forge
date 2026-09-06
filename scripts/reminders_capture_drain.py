"""Reminders capture drain implementation; invoked by the shell entry point."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from typing import Any
from pathlib import Path

from forge_tasks_world.capture_receipts import CaptureReceipts

list_name = os.environ["DRAIN_LIST"]
dry_run = os.environ["DRAIN_DRY_RUN"] == "1"
do_complete = os.environ["DRAIN_DO_COMPLETE"] == "1"
forge_bin = os.environ["DRAIN_FORGE_BIN"]
forge_dir = os.environ["DRAIN_FORGE_DIR"]

uri_re = re.compile(r"^(https?|message|file|obsidian|bookends):", re.I)


def looks_like_uri(notes: str | None) -> bool:
    """Return True when notes are a single-line URI suitable for --link."""
    if not notes:
        return False
    text = notes.strip()
    return bool(uri_re.match(text)) and "\n" not in text


def run_jxa(script: str) -> subprocess.CompletedProcess[str]:
    """Run a JXA programme via osascript stdin."""
    return subprocess.run(
        ["osascript", "-l", "JavaScript"],
        input=script,
        capture_output=True,
        text=True,
        check=False,
    )


def jxa_json(script: str) -> Any:
    """Run JXA and parse the last JSON line from stdout or stderr."""
    proc = run_jxa(script)
    blob = (proc.stdout or "").strip() or (proc.stderr or "").strip()
    if proc.returncode != 0 and not blob:
        raise RuntimeError("osascript failed with no output")
    if not blob:
        raise RuntimeError("empty Reminders response")
    # Prefer the last line that parses as JSON (ignore osascript chatter).
    last_error: Exception | None = None
    for line in reversed(blob.splitlines()):
        line = line.strip()
        if not line:
            continue
        try:
            return json.loads(line)
        except json.JSONDecodeError as exc:
            last_error = exc
            continue
    if proc.returncode != 0:
        raise RuntimeError(blob)
    raise RuntimeError(f"no JSON in osascript output: {blob!r}") from last_error


def fetch_reminders(name: str) -> dict[str, Any]:
    """Return incomplete reminders from a Reminders list via JXA."""
    name_json = json.dumps(name)
    script = f"""
const listName = {name_json};
const app = Application("Reminders");
const lists = app.lists.whose({{name: listName}})();
if (!lists.length) {{
  console.log(JSON.stringify({{error: "list_not_found", list: listName}}));
}} else {{
  const reminders = lists[0].reminders.whose({{completed: false}})();
  const items = [];
  for (const r of reminders) {{
    let title = "";
    try {{ title = String(r.name() || ""); }} catch (e) {{ title = ""; }}
    let notes = null;
    try {{
      const body = r.body();
      if (body != null && String(body).length > 0 && String(body) !== "null") {{
        notes = String(body);
      }}
    }} catch (e) {{}}
    let id = "";
    try {{ id = String(r.id()); }} catch (e) {{ id = ""; }}
    items.push({{id: id, title: title, notes: notes}});
  }}
  console.log(JSON.stringify({{list: listName, reminders: items}}));
}}
"""
    result = jxa_json(script)
    if not isinstance(result, dict):
        raise RuntimeError(f"unexpected Reminders payload: {result!r}")
    return result


def complete_reminder(rem_id: str) -> None:
    """Mark a Reminders item completed by AppleScript id."""
    id_json = json.dumps(rem_id)
    script = f"""
const id = {id_json};
const app = Application("Reminders");
const rem = app.reminders.byId(id);
rem.completed = true;
console.log(JSON.stringify({{ok: true, id: id}}));
"""
    result = jxa_json(script)
    if not isinstance(result, dict) or not result.get("ok"):
        raise RuntimeError(f"failed to complete reminder {rem_id}: {result!r}")


try:
    payload = fetch_reminders(list_name)
except (RuntimeError, json.JSONDecodeError, IndexError) as exc:
    print(f"failed to read Reminders list {list_name!r}: {exc}", file=sys.stderr)
    print(
        json.dumps(
            {
                "ok": False,
                "list": list_name,
                "error": str(exc),
                "scanned": 0,
                "captured": [],
                "failed": [],
                "completed": [],
                "skipped": [],
                "dry_run": dry_run,
            },
            indent=2,
        )
    )
    sys.exit(1)

if payload.get("error") == "list_not_found":
    print(f"Reminders list not found: {list_name}", file=sys.stderr)
    print(
        json.dumps(
            {
                "ok": False,
                "list": list_name,
                "error": "list_not_found",
                "scanned": 0,
                "captured": [],
                "failed": [],
                "completed": [],
                "skipped": [],
                "dry_run": dry_run,
            },
            indent=2,
        )
    )
    sys.exit(1)

reminders = payload.get("reminders") or []
captured: list[dict[str, Any]] = []
failed: list[dict[str, Any]] = []
completed_items: list[dict[str, Any]] = []
skipped: list[dict[str, Any]] = []

# Hold a local process lock across the hand-off. Dry runs create no receipts.
receipts = CaptureReceipts(Path(forge_dir)) if not dry_run else None

for rem in reminders:
    rem_id = (rem.get("id") or "").strip()
    title = (rem.get("title") or "").strip()
    notes = rem.get("notes")
    if isinstance(notes, str):
        notes = notes.strip() or None
    else:
        notes = None

    if not title:
        skipped.append({"id": rem_id, "reason": "empty_title"})
        continue

    if title.startswith("Forge · ") or title.startswith("Kanban · "):
        skipped.append({"id": rem_id, "title": title, "reason": "sentinel"})
        continue

    entry: dict[str, Any] = {"id": rem_id, "title": title}
    if notes:
        entry["notes"] = notes

    if dry_run:
        entry["action"] = "would_capture"
        captured.append(entry)
        continue

    if not rem_id:
        entry["error"] = "missing source id; cannot safely capture"
        failed.append(entry)
        continue

    receipt = receipts.entries.get(rem_id)
    if receipt is not None:
        if not isinstance(receipt, dict) or not receipt.get("sp_id"):
            entry["error"] = "previous capture unconfirmed; reconcile SP and the capture receipt before retrying"
            failed.append(entry)
            continue
        entry["sp_id"] = receipt["sp_id"]
        entry["backend"] = "super-productivity"
        entry["action"] = "reuse-capture"
    else:
        receipts.record(rem_id, None)
        cmd = [forge_bin, "capture", title, "--source", "reminders", "--json"]
        if notes and looks_like_uri(notes):
            cmd += ["--link", notes]
        elif notes:
            cmd += ["--note", notes]

        try:
            proc = subprocess.run(
                cmd,
                cwd=forge_dir,
                capture_output=True,
                text=True,
                check=False,
            )
        except OSError as exc:
            entry["error"] = str(exc)
            failed.append(entry)
            continue

        if proc.returncode != 0:
            detail = (proc.stderr or proc.stdout or "").strip()
            entry["error"] = detail or f"forge capture exit {proc.returncode}"
            failed.append(entry)
            print(f"capture failed: {title}: {entry['error']}", file=sys.stderr)
            continue

        try:
            cap = json.loads(proc.stdout)
            if not isinstance(cap, dict):
                raise ValueError("capture response must be a JSON object")
            task_id = cap.get("id")
            if cap.get("backend") != "super-productivity":
                raise ValueError("capture did not confirm the Super Productivity backend")
            if not isinstance(task_id, str) or not task_id.strip():
                raise ValueError("capture did not return a Super Productivity task id")
            entry["sp_id"] = task_id
            entry["backend"] = cap["backend"]
        except ValueError as exc:
            entry["error"] = f"capture unconfirmed; reminder left incomplete: {exc}"
            failed.append(entry)
            print(entry["error"], file=sys.stderr)
            continue
        receipts.record(rem_id, entry["sp_id"])

    captured.append(entry)

    if do_complete and rem_id:
        try:
            complete_reminder(rem_id)
            completed_items.append({"id": rem_id, "title": title, "sp_id": entry.get("sp_id")})
        except RuntimeError as exc:
            entry_fail = {
                "id": rem_id,
                "title": title,
                "sp_id": entry.get("sp_id"),
                "error": f"captured but not completed: {exc}",
            }
            failed.append(entry_fail)
            print(entry_fail["error"], file=sys.stderr)

if receipts is not None:
    receipts.close()

summary = {
    "ok": len(failed) == 0,
    "list": list_name,
    "scanned": len(reminders),
    "captured": captured,
    "failed": failed,
    "completed": completed_items,
    "skipped": skipped,
    "dry_run": dry_run,
    "complete_after_capture": bool(do_complete and not dry_run),
}
print(json.dumps(summary, indent=2))
sys.exit(0 if summary["ok"] else 1)

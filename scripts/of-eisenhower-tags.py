#!/usr/bin/env python3
"""Tag SP tasks from OmniFocus flags and Forge URGENT projects.

- OmniFocus flagged pending → Super Productivity ``important`` (``EM_IMPORTANT``)
- Forge projects with ``URGENT ⚠️`` → open SP tasks in the mapped project get
  ``urgent`` (``EM_URGENT``)

These are the Eisenhower-matrix tags already present in SP (titles ``important``
/ ``urgent``; ids ``EM_IMPORTANT`` / ``EM_URGENT``).
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from forge_tasks_world.superproductivity import (  # noqa: E402
    INBOX_PROJECT_ID,
    SuperProductivityError,
    config_from_file,
    open_client,
)

OF_ID_RE = re.compile(r"\[forge:of-id:([^\]]+)\]")
IMPORTANT_ID = "EM_IMPORTANT"
URGENT_ID = "EM_URGENT"

OMNIJS_FLAGGED = r"""
function() {
  var rows = [];
  var all = flattenedTasks || [];
  for (var i = 0; i < all.length; i++) {
    var t = all[i];
    if (t.completed) continue;
    if (!t.flagged) continue;
    var proj = null;
    try { proj = t.containingProject ? t.containingProject.name : null; } catch (e) {}
    rows.push({id: t.id.primaryKey, name: t.name, ofProjectName: proj, flagged: true});
  }
  return JSON.stringify({count: rows.length, tasks: rows});
}
"""


def resolve_forge_home() -> Path:
    """Return Forge home containing config.yaml."""
    home = Path.home()
    for candidate in (
        home / "Documents/Software/Forge",
        home / "Documents/Forge",
        home / "Documents/Work/Projects/Forge",
    ):
        if (candidate / "config.yaml").exists():
            return candidate
    return home / "Documents/Software/Forge"


def export_flagged_omnifocus() -> dict[str, Any]:
    """Return pending OmniFocus tasks that are flagged."""
    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False) as handle:
        handle.write(OMNIJS_FLAGGED.strip())
        js_path = handle.name
    script = f"""
ObjC.import("Foundation");
const read = (path) => ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null));
Application("OmniFocus").evaluateJavascript("(" + read("{js_path}") + ")()");
"""
    raw = subprocess.check_output(["osascript", "-l", "JavaScript"], input=script, text=True)
    return json.loads(raw)


def board_urgent_projects() -> list[str]:
    """Return Forge board project names carrying URGENT."""
    board = json.loads(subprocess.check_output(["forge", "board", "--json"], text=True))
    names: list[str] = []
    for project in board.get("projects") or []:
        tags = list(project.get("tags") or []) + list(project.get("metaTags") or [])
        if any("URGENT" in str(tag) for tag in tags):
            names.append(str(project["name"]))
    return names


def index_sp_tasks(client: Any) -> tuple[dict[str, dict], dict[str, list[dict]]]:
    """Index open SP tasks by OmniFocus id and by SP project id."""
    by_of: dict[str, dict] = {}
    by_project: dict[str, list[dict]] = {}
    project_ids = [p["id"] for p in client.projects()] + [INBOX_PROJECT_ID]
    for project_id in dict.fromkeys(project_ids):
        by_project.setdefault(project_id, [])
        try:
            tasks = client.tasks(project_id, include_done=False)
        except SuperProductivityError:
            continue
        for task in tasks:
            if task.get("isDone"):
                continue
            by_project[project_id].append(task)
            match = OF_ID_RE.search(str(task.get("notes") or ""))
            if match:
                by_of[match.group(1)] = task
    return by_of, by_project


def main() -> int:
    """Dry-run or apply Eisenhower tags from OF flags and Forge URGENT."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--forge-home", type=Path, default=None)
    parser.add_argument("--apply", action="store_true", help="Write tagIds (default: dry-run)")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    forge_home = (args.forge_home or resolve_forge_home()).expanduser().resolve()
    client = open_client(forge_home)
    tag_titles = {str(t["id"]): str(t.get("title") or t["id"]) for t in client.tags()}
    for needed in (IMPORTANT_ID, URGENT_ID):
        if needed not in tag_titles:
            print(f"missing SP tag id {needed}; create Eisenhower tags first", file=sys.stderr)
            return 1

    print("Exporting flagged OmniFocus tasks…", file=sys.stderr)
    flagged = export_flagged_omnifocus()
    urgent_projects = board_urgent_projects()
    config = config_from_file(forge_home / "config.yaml")
    name_to_spid = dict(config.project_ids or {})

    print("Indexing Super Productivity tasks…", file=sys.stderr)
    by_of, by_project = index_sp_tasks(client)

    updates: dict[str, dict[str, Any]] = {}
    missing_flagged: list[dict[str, Any]] = []

    for task in flagged.get("tasks") or []:
        sp = by_of.get(str(task["id"]))
        if not sp:
            missing_flagged.append(task)
            continue
        tid = str(sp["id"])
        entry = updates.setdefault(tid, {"task": sp, "add": set(), "reasons": []})
        entry["add"].add(IMPORTANT_ID)
        entry["reasons"].append("OF flagged")

    unmapped_urgent: list[str] = []
    for name in urgent_projects:
        spid = name_to_spid.get(name)
        if not spid:
            unmapped_urgent.append(name)
            continue
        for sp in by_project.get(spid, []):
            tid = str(sp["id"])
            entry = updates.setdefault(tid, {"task": sp, "add": set(), "reasons": []})
            entry["add"].add(URGENT_ID)
            entry["reasons"].append(f"Forge URGENT:{name}")

    patches: list[dict[str, Any]] = []
    already = 0
    for tid, info in updates.items():
        task = info["task"]
        current = list(task.get("tagIds") or [])
        needed = [tag for tag in sorted(info["add"]) if tag not in current]
        if not needed:
            already += 1
            continue
        patches.append(
            {
                "id": tid,
                "title": task.get("title"),
                "projectId": task.get("projectId"),
                "add": needed,
                "add_titles": [tag_titles[t] for t in needed],
                "newTagIds": current + needed,
                "reasons": info["reasons"],
            }
        )

    summary = {
        "of_flagged": flagged.get("count"),
        "forge_urgent_projects": urgent_projects,
        "unmapped_urgent_projects": unmapped_urgent,
        "missing_flagged_sp": len(missing_flagged),
        "already_tagged": already,
        "to_update": len(patches),
        "dry_run": not args.apply,
    }

    applied = 0
    failed: list[dict[str, Any]] = []
    if args.apply:
        for patch in patches:
            try:
                client.update_task(patch["id"], {"tagIds": patch["newTagIds"]})
                applied += 1
            except SuperProductivityError as exc:
                failed.append({"id": patch["id"], "title": patch["title"], "error": str(exc)})

    result = {
        **summary,
        "applied": applied,
        "failed": failed,
        "patches": patches,
        "missing_flagged_sample": [
            {"id": t.get("id"), "title": t.get("name"), "project": t.get("ofProjectName")}
            for t in missing_flagged[:20]
        ],
    }

    if args.json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        print("## OF flag / Forge URGENT → SP Eisenhower tags")
        print(f"OF flagged pending: {summary['of_flagged']}")
        print(f"Forge URGENT projects: {summary['forge_urgent_projects']}")
        if unmapped_urgent:
            print(f"URGENT unmapped: {unmapped_urgent}")
        print(f"to update: {len(patches)}  already ok: {already}  missing SP for flagged: {len(missing_flagged)}")
        print(f"\nUsing SP tags: {IMPORTANT_ID}={tag_titles[IMPORTANT_ID]!r}, {URGENT_ID}={tag_titles[URGENT_ID]!r}")
        print("\nUpdates:")
        for patch in patches[:50]:
            print(f"  +{patch['add_titles']} | {str(patch['title'])[:55]} | {patch['reasons']}")
        if len(patches) > 50:
            print(f"  … and {len(patches) - 50} more")
        if missing_flagged:
            print("\nFlagged OF with no imported SP task (sample):")
            for task in missing_flagged[:15]:
                print(f"  {task.get('name')} | {task.get('ofProjectName')}")
        if args.apply:
            print(f"\napplied: {applied}  failed: {len(failed)}")
        else:
            print("\nDry-run only. Apply with:\n  python3 scripts/of-eisenhower-tags.py --apply")

    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Import Forge-linked OmniFocus tasks into TASKS.toml and refresh world.db."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
from collections import defaultdict
from datetime import datetime
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from forge_tasks_world.capture import task_db_path  # noqa: E402
from forge_tasks_world.of_mapping import (  # noqa: E402
    PROJECT_FOLDER_ALIASES,
    is_waiting,
    keep_task,
    resolve_folder,
)
from forge_tasks_world.toml_io import (  # noqa: E402
    ProjectTasks,
    TaskRecord,
    load_project_tasks,
    project_tasks_path,
    write_project_tasks,
)
from forge_tasks_world.world_db import WorldDatabase  # noqa: E402

OMNIJS_EXPORT = r"""
function() {
  function iso(d) {
    if (!d) return null;
    try { return d.toISOString(); } catch (e) { return null; }
  }
  function tagPath(tag) {
    var parts = [];
    var c = tag;
    while (c) { parts.unshift(c.name || ""); c = c.parent; }
    return parts.join(":");
  }
  function forgeFolderFromTags(item) {
    var tags = item.tags || [];
    for (var i = 0; i < tags.length; i++) {
      var p = tagPath(tags[i]);
      if (p.indexOf("🔥 Forge:") === 0) return p.slice("🔥 Forge:".length);
    }
    return null;
  }
  function summarizeTask(t) {
    var proj = null;
    try { proj = t.containingProject ? t.containingProject.name : null; } catch (e) {}
    return {
      id: t.id.primaryKey,
      name: t.name,
      note: t.note || "",
      completed: !!t.completed,
      flagged: !!t.flagged,
      due: iso(t.dueDate),
      defer: iso(t.deferDate),
      ofProjectName: proj,
      forgeFolder: forgeFolderFromTags(t)
    };
  }
  function summarizeProject(p) {
    var tasks = [];
    var ft = p.flattenedTasks || [];
    for (var i = 0; i < ft.length; i++) tasks.push(summarizeTask(ft[i]));
    return {
      name: p.name,
      id: p.id.primaryKey,
      forgeFolder: forgeFolderFromTags(p),
      tasks: tasks
    };
  }
  var tasks = [];
  var all = flattenedTasks || [];
  for (var i = 0; i < all.length; i++) tasks.push(summarizeTask(all[i]));
  var projects = [];
  var fps = flattenedProjects || [];
  for (var j = 0; j < fps.length; j++) projects.push(summarizeProject(fps[j]));
  return JSON.stringify({ tasks: tasks, projects: projects }, null, 0);
}
"""


def resolve_forge_home() -> Path:
    home = Path.home()
    for candidate in (
        home / "Documents/Software/Forge",
        home / "Documents/Forge",
        home / "Documents/Work/Projects/Forge",
    ):
        if (candidate / "config.yaml").exists() or (candidate / "config.sample.yaml").exists():
            return candidate
    return home / "Documents/Software/Forge"


def export_omnifocus() -> dict:
    """Pull live tasks and projects from OmniFocus via OmniJS."""
    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False) as handle:
        handle.write(OMNIJS_EXPORT.strip())
        js_path = handle.name
    script = f"""
ObjC.import("Foundation");
const read = (path) => ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null));
const OmniFocus = Application("OmniFocus");
OmniFocus.evaluateJavascript("(" + read("{js_path}") + ")()");
"""
    raw = subprocess.check_output(["osascript", "-l", "JavaScript"], input=script, text=True)
    return json.loads(raw)


def load_forge_board(forge_root: Path) -> tuple[dict[str, Path], dict[str, str | None]]:
    """Return project paths and column names from `forge board --json`."""
    board_json = subprocess.check_output(
        ["forge", "board", "--json"], cwd=forge_root, text=True
    )
    board = json.loads(board_json)
    paths = {project["name"]: Path(project["path"]) for project in board.get("projects", [])}
    columns = {project["name"]: project.get("column") for project in board.get("projects", [])}
    return paths, columns


def parse_message_link(note: str) -> str | None:
    if not note:
        return None
    match = re.search(r"<(message:[^>]+)>", note)
    if match:
        return match.group(1)
    match = re.search(r"(message:[^\s>]+)", note)
    return match.group(1) if match else None


def fmt_date(iso: str | None) -> str | None:
    if not iso:
        return None
    try:
        parsed = datetime.fromisoformat(iso.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.hour or parsed.minute:
        return parsed.strftime("%Y-%m-%d %H:%M")
    return parsed.strftime("%Y-%m-%d")


def of_task_to_record(task: dict) -> TaskRecord:
    """Convert one OmniFocus export row into a TOML task record."""
    title = (task.get("name") or "").strip().replace("\n", " ")
    note = (task.get("note") or "").strip()
    links: dict[str, str] = {}
    message = parse_message_link(note)
    if message:
        links["mail"] = message

    task_notes = None
    if note and not message:
        task_notes = note
    elif note and message:
        cleaned = re.sub(r"<message:[^>]+>", "", note).strip()
        if cleaned and cleaned not in title:
            task_notes = cleaned

    section = "done" if task.get("completed") else "next"
    if not task.get("completed") and is_waiting(task):
        section = "waiting"

    return TaskRecord(
        id=str(task["id"]),
        title=title,
        section=section,
        due=fmt_date(task.get("due")),
        defer=fmt_date(task.get("defer")),
        flagged=bool(task.get("flagged")),
        links=links,
        notes=task_notes,
    )


def build_folder_tasks(of_data: dict, forge_paths: dict[str, Path]) -> dict[str, dict[str, dict]]:
    """Group OmniFocus tasks by Forge folder."""
    project_forge = {project["name"]: project.get("forgeFolder") for project in of_data["projects"]}
    project_ids = {project["id"] for project in of_data["projects"]}
    folder_tasks: dict[str, dict[str, dict]] = defaultdict(dict)

    for task in of_data["tasks"]:
        if not keep_task(task, project_ids):
            continue
        folder = resolve_folder(task, project_forge, forge_paths)
        if folder and folder in forge_paths:
            folder_tasks[folder][task["id"]] = task

    for project in of_data["projects"]:
        folder = project.get("forgeFolder")
        if not folder:
            folder = PROJECT_FOLDER_ALIASES.get(project["name"])
            if folder is None and project["name"] in forge_paths:
                folder = project["name"]
        if not folder or folder not in forge_paths:
            continue
        for task in project["tasks"]:
            if keep_task(task, project_ids):
                folder_tasks[folder][task["id"]] = task

    for folder in list(folder_tasks):
        tasks_map = folder_tasks[folder]
        active = [task for task in tasks_map.values() if not task.get("completed")]
        if len(active) > 1:
            for task_id in list(tasks_map):
                if task_id in project_ids:
                    del tasks_map[task_id]

    return folder_tasks


def write_tasks_toml(folder: str, project_dir: Path, tasks: list[dict]) -> ProjectTasks:
    """Write OmniFocus tasks to TASKS.toml, preserving project notes."""
    toml_path = project_tasks_path(project_dir)
    notes_body = ""
    if toml_path.exists():
        notes_body = load_project_tasks(toml_path).notes_body

    records = [of_task_to_record(task) for task in tasks]
    sort_key = lambda item: (item.due or "9999", item.title.lower())
    records.sort(key=lambda item: ({"next": 0, "waiting": 1, "done": 2, "someday": 3}[item.section], sort_key(item)))

    project_tasks = ProjectTasks(project=folder, notes_body=notes_body, tasks=records, path=toml_path)
    write_project_tasks(project_tasks, toml_path)
    return project_tasks


def ingest_project_tasks(
    forge_home: Path,
    forge_paths: dict[str, Path],
    columns: dict[str, str | None],
) -> int:
    """Refresh tasks.db from every board project with TASKS.toml."""
    db = WorldDatabase(task_db_path(forge_home))
    ingested = 0
    try:
        for folder in sorted(forge_paths):
            project_dir = forge_paths[folder]
            toml_path = project_tasks_path(project_dir)
            if not toml_path.exists():
                continue
            project_tasks = load_project_tasks(toml_path)
            db.ingest_project(
                project_path=project_dir,
                project_name=folder,
                column_name=columns.get(folder),
                project_tasks=project_tasks,
                tasks_path=toml_path,
            )
            ingested += 1
    finally:
        db.close()
    return ingested


def retire_legacy_md(forge_paths: dict[str, Path]) -> int:
    """Remove TASKS.md wherever TASKS.toml already exists on the board."""
    retired = 0
    for project_dir in forge_paths.values():
        toml_path = project_tasks_path(project_dir)
        if retire_tasks_md(project_dir, toml_path):
            retired += 1
    return retired


def retire_tasks_md(project_dir: Path, toml_path: Path) -> bool:
    """Remove legacy TASKS.md once TASKS.toml exists."""
    md_path = project_dir / "TASKS.md"
    if md_path.exists() and toml_path.exists():
        md_path.unlink()
        return True
    return False


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Import OmniFocus tasks into TASKS.toml and refresh world.db.",
    )
    parser.add_argument(
        "--forge-home",
        default=str(resolve_forge_home()),
        help="Forge home directory",
    )
    parser.add_argument(
        "--keep-md",
        action="store_true",
        help="Keep legacy TASKS.md files (default: retire them)",
    )
    parser.add_argument(
        "--no-ingest",
        action="store_true",
        help="Write TASKS.toml only; do not refresh world.db",
    )
    args = parser.parse_args()

    forge_home = Path(args.forge_home).expanduser()
    forge_paths, columns = load_forge_board(forge_home)
    of_data = export_omnifocus()
    folder_tasks = build_folder_tasks(of_data, forge_paths)

    updated: list[tuple[str, ProjectTasks, Path]] = []
    retired = 0

    for folder in sorted(folder_tasks):
        tasks = list(folder_tasks[folder].values())
        if not tasks:
            continue
        project_dir = forge_paths[folder]
        project_tasks = write_tasks_toml(folder, project_dir, tasks)
        toml_path = project_tasks_path(project_dir)
        updated.append((folder, project_tasks, toml_path))
        if not args.keep_md and retire_tasks_md(project_dir, toml_path):
            retired += 1

    print(f"Updated {len(updated)} TASKS.toml file(s)")
    for folder, project_tasks, toml_path in updated:
        counts = {
            section: len(project_tasks.tasks_in(section))
            for section in ("next", "waiting", "done")
        }
        print(
            f"  {folder}: next={counts['next']} waiting={counts['waiting']} "
            f"done={counts['done']}"
        )
        print(f"    {toml_path}")

    if not args.keep_md:
        extra_retired = retire_legacy_md(forge_paths)
        if extra_retired:
            retired += extra_retired
        print(f"\nRetired {retired} TASKS.md file(s)")

    unmapped = sorted(set(forge_paths) - set(folder_tasks))

    if not args.no_ingest and updated:
        ingested = ingest_project_tasks(forge_home, forge_paths, columns)
        if ingested:
            print(f"Ingested {ingested} project(s) into {task_db_path(forge_home)}")

    print(f"\nForge projects without mapped OmniFocus tasks: {len(unmapped)}")
    if unmapped:
        print("  (not creating TASKS.toml — capture into the Forge inbox, or add 🔥 Forge: tags in OmniFocus)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

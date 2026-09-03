#!/usr/bin/env python3
"""Forge project tasks: per-project TASKS.toml and SQLite task index (.forge/world.db)."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import date
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from forge_tasks_world.capture import task_db_path  # noqa: E402
from forge_tasks_world.md_convert import convert_tasks_md_file  # noqa: E402
from forge_tasks_world.of_mapping import PROJECT_FOLDER_ALIASES  # noqa: F401
from forge_tasks_world.show import render_many  # noqa: E402
from forge_tasks_world.toml_io import (  # noqa: E402
    ProjectTasks,
    apply_checked_completions,
    load_project_tasks,
    project_tasks_path,
    write_project_tasks,
)
from forge_tasks_world.world_db import WorldDatabase  # noqa: E402


def resolve_forge_home() -> Path:
    """Locate Forge home from config search paths."""
    home = Path.home()
    candidates = [
        home / "Documents/Software/Forge",
        home / "Documents/Forge",
        home / "Documents/Work/Projects/Forge",
    ]
    for candidate in candidates:
        if (candidate / "config.yaml").exists() or (candidate / "config.sample.yaml").exists():
            return candidate
    return candidates[0]


def task_index_path(forge_home: Path) -> Path:
    """Return the canonical task database path (tasks.db, migrating world.db)."""
    return task_db_path(forge_home)


def load_board_projects(forge_home: Path) -> list[dict]:
    """Return Forge board projects via `forge board --json`."""
    result = subprocess.run(
        ["forge", "board", "--json"],
        cwd=forge_home,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "forge board --json failed")
    board = json.loads(result.stdout)
    return board.get("projects") or []


def resolve_project_tasks(project_dir: Path, *, convert_md: bool) -> Path | None:
    """Return a TASKS.toml path, optionally converting legacy TASKS.md."""
    toml_path = project_tasks_path(project_dir)
    if toml_path.exists():
        return toml_path
    md_path = project_dir / "TASKS.md"
    if convert_md and md_path.exists():
        convert_tasks_md_file(md_path, toml_path)
        return toml_path
    return None


def cmd_convert(args: argparse.Namespace) -> int:
    forge_home = Path(args.forge_home).expanduser()
    converted = 0
    skipped = 0

    if args.project:
        projects = load_board_projects(forge_home)
        match = [project for project in projects if args.project in project["name"]]
        if not match:
            print(f"No project matching '{args.project}'", file=sys.stderr)
            return 1
        targets = [Path(project["path"]) for project in match]
    else:
        targets = [Path(project["path"]) for project in load_board_projects(forge_home)]

    for project_dir in targets:
        md_path = project_dir / "TASKS.md"
        toml_path = project_tasks_path(project_dir)
        if not md_path.exists():
            skipped += 1
            continue
        convert_tasks_md_file(md_path, toml_path)
        print(f"converted {toml_path}")
        converted += 1

    print(f"\nConverted {converted} TASKS.toml file(s); skipped {skipped} without TASKS.md")
    return 0


def match_projects(projects: list[dict], needle: str | None) -> list[dict]:
    """Filter board projects by optional name substring."""
    if not needle:
        return projects
    matches = [project for project in projects if needle.lower() in project["name"].lower()]
    return matches


def cmd_show(args: argparse.Namespace) -> int:
    forge_home = Path(args.forge_home).expanduser()
    projects = load_board_projects(forge_home)
    matches = match_projects(projects, args.project)

    if args.project and not matches:
        print(f"No project matching '{args.project}'", file=sys.stderr)
        return 1

    items: list[tuple[ProjectTasks, str | None]] = []
    for project in matches:
        project_dir = Path(project["path"])
        toml_path = project_tasks_path(project_dir)
        if not toml_path.exists():
            if args.project:
                print(f"No TASKS.toml at {toml_path}", file=sys.stderr)
                return 1
            continue
        project_tasks = load_project_tasks(toml_path)
        items.append((project_tasks, project.get("column")))

    if not items:
        print("No TASKS.toml files found on the board.")
        return 0

    print(
        render_many(
            items,
            show_ids=args.ids,
            width=0 if args.no_wrap else args.width,
        )
    )
    return 0


def cmd_format(args: argparse.Namespace) -> int:
    """Rewrite TASKS.toml files using the human-friendly writer."""
    forge_home = Path(args.forge_home).expanduser()
    projects = load_board_projects(forge_home)
    matches = match_projects(projects, args.project)

    if args.project and not matches:
        print(f"No project matching '{args.project}'", file=sys.stderr)
        return 1

    formatted = 0
    skipped = 0
    for project in matches:
        toml_path = project_tasks_path(Path(project["path"]))
        if not toml_path.exists():
            skipped += 1
            continue
        project_tasks = load_project_tasks(toml_path)
        apply_checked_completions(project_tasks)
        write_project_tasks(project_tasks, toml_path)
        print(f"  formatted {toml_path}")
        formatted += 1

    print(f"\nFormatted {formatted} TASKS.toml file(s); skipped {skipped}")
    return 0


def cmd_ingest(args: argparse.Namespace) -> int:
    forge_home = Path(args.forge_home).expanduser()
    db = WorldDatabase(task_index_path(forge_home))
    projects = load_board_projects(forge_home)

    ingested = 0
    skipped = 0
    task_count = 0
    removed = 0

    try:
        for project in projects:
            project_dir = Path(project["path"])
            tasks_file = resolve_project_tasks(project_dir, convert_md=args.convert_md)
            if tasks_file is None:
                skipped += 1
                continue
            project_tasks = load_project_tasks(tasks_file)
            if apply_checked_completions(project_tasks):
                write_project_tasks(project_tasks, tasks_file)
                project_tasks = load_project_tasks(tasks_file)
            upserted, deleted = db.ingest_project(
                project_path=project_dir,
                project_name=project["name"],
                column_name=project.get("column"),
                project_tasks=project_tasks,
                tasks_path=tasks_file,
            )
            ingested += 1
            task_count += upserted
            removed += deleted
            print(f"  {project['name']}: {upserted} task(s)")
    finally:
        db.close()

    print(
        f"\nIngested {ingested} project(s), {task_count} task(s); "
        f"removed {removed} stale; skipped {skipped}"
    )
    print(f"Task index: {task_index_path(forge_home)}")
    return 0


def cmd_due(args: argparse.Namespace) -> int:
    forge_home = Path(args.forge_home).expanduser()
    db = WorldDatabase(task_index_path(forge_home))
    try:
        items = db.due_tasks(
            horizon_days=args.days,
            include_overdue=not args.no_overdue,
            assignee=args.assignee,
        )
    finally:
        db.close()

    if not items:
        print("No due tasks in horizon.")
        return 0

    today = date.today()
    print(f"Due tasks (horizon {args.days} day(s), from {today.isoformat()})\n")
    for item in items:
        ctx = f" @ctx({', '.join(item.contexts)})" if item.contexts else ""
        people = (
            " "
            + " ".join(f"#{name}" for name in item.assignees)
            if item.assignees
            else ""
        )
        print(
            f"{item.due:16}  {item.project_name:32}  {item.title}{ctx}{people}  ({item.task_id})"
        )
    return 0


def cmd_status(args: argparse.Namespace) -> int:
    forge_home = Path(args.forge_home).expanduser()
    db_path = task_index_path(forge_home)
    if not db_path.exists():
        print(
            f"No task index yet at {db_path}\n"
            "Run: forge-tasks-world.py ingest --convert-md"
        )
        return 0
    db = WorldDatabase(db_path)
    try:
        stats = db.status()
    finally:
        db.close()
    print(f"Task index: {stats['db_path']}")
    print(f"Projects:   {stats['projects']}")
    print(f"Tasks:      {stats['tasks']} ({stats['open_tasks']} open)")
    print(f"Inbox:      {stats.get('inbox', 0)}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Forge project tasks — TASKS.toml per project and SQLite task index.",
    )
    parser.add_argument(
        "--forge-home",
        default=str(resolve_forge_home()),
        help="Forge home directory (default: auto-detected)",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    convert = sub.add_parser("convert", help="Convert TASKS.md → TASKS.toml")
    convert.add_argument("project", nargs="?", help="Project name substring (default: all)")
    convert.set_defaults(func=cmd_convert)

    ingest = sub.add_parser("ingest", help="Ingest TASKS.toml files into world.db")
    ingest.add_argument(
        "--convert-md",
        action="store_true",
        help="Legacy: convert TASKS.md when TASKS.toml is missing (prefer sync-of-tasks-from-of.py)",
    )
    ingest.set_defaults(func=cmd_ingest)

    due = sub.add_parser("due", help="List due tasks from world.db")
    due.add_argument("--days", type=int, default=7, help="Horizon in days (default: 7)")
    due.add_argument("--no-overdue", action="store_true", help="Hide overdue tasks")
    due.add_argument("--assignee", help="Filter to #Person assignee")
    due.set_defaults(func=cmd_due)

    status = sub.add_parser("status", help="Show task index summary")
    status.set_defaults(func=cmd_status)

    show = sub.add_parser("show", help="Pretty-print TASKS.toml (read-only)")
    show.add_argument(
        "project",
        nargs="?",
        help="Project name substring (default: all board projects with TASKS.toml)",
    )
    show.add_argument("--ids", action="store_true", help="Show Forge task ids")
    show.add_argument("--width", type=int, default=88, help="Wrap width (0 = no wrap)")
    show.add_argument("--no-wrap", action="store_true", help="Disable line wrapping")
    show.set_defaults(func=cmd_show)

    fmt = sub.add_parser("format", help="Rewrite TASKS.toml with the readable writer")
    fmt.add_argument("project", nargs="?", help="Project name substring (default: all)")
    fmt.set_defaults(func=cmd_format)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())

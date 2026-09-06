#!/usr/bin/env python3
"""Command-line Super Productivity adapter (safe by default)."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from forge_tasks_world.capture import task_db_path  # noqa: E402
from forge_tasks_world.superproductivity import (  # noqa: E402
    SuperProductivityClient,
    SuperProductivityError,
    board_column_tags_from_yaml,
    config_from_file,
    keychain_token,
    load_ledger,
    mirror_column_tags,
    refresh_project,
    save_ledger,
    sync_lock,
    sync_project,
)
from forge_tasks_world.toml_io import load_project_tasks, project_tasks_path  # noqa: E402
from forge_tasks_world.world_db import WorldDatabase  # noqa: E402


def _board_project_paths(forge_home: Path) -> dict[str, Path]:
    """Resolve mapped project folders from ``forge board --json`` when available."""
    import json
    import shutil
    import subprocess

    forge_bin = shutil.which("forge")
    if not forge_bin:
        return {}
    try:
        result = subprocess.run(
            [forge_bin, "board", "--json"],
            cwd=str(forge_home),
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return {}
    if result.returncode != 0 or not result.stdout.strip():
        return {}
    try:
        board = json.loads(result.stdout)
    except json.JSONDecodeError:
        return {}
    paths: dict[str, Path] = {}
    for project in board.get("projects") or []:
        name = project.get("name")
        path = project.get("path")
        if name and path:
            paths[str(name)] = Path(path)
    return paths


def _project_dir(forge_home: Path, name: str, board_paths: dict[str, Path] | None = None) -> Path:
    """Return the on-disk folder for a mapped project name."""
    board_paths = board_paths if board_paths is not None else _board_project_paths(forge_home)
    if name in board_paths:
        return board_paths[name]
    if name == "Forge":
        return forge_home
    return forge_home / name


def _print(result: Any, as_json: bool) -> None:
    """Print a structured result as JSON or a compact text summary."""
    if as_json:
        print(json.dumps(result, indent=2, sort_keys=True))
        return
    if isinstance(result, list):
        for item in result:
            _print_one(item)
        return
    _print_one(result)


def _print_one(result: Any) -> None:
    """Print one result object compactly."""
    if isinstance(result, dict) and "project" in result:
        conflicts = len(result.get("conflicts") or [])
        print(
            f"{result['project']}: {len(result.get('changes') or [])} change(s), "
            f"{conflicts} conflict(s), applied={result.get('applied', False)}"
        )
        return
    print(result)


def _selected_projects(config, names: list[str]) -> dict[str, str]:
    """Return mapped projects, optionally filtered by name."""
    projects = config.project_ids or {}
    if not names:
        return dict(projects)
    missing = [name for name in names if name not in projects]
    if missing:
        raise SuperProductivityError("unmapped project(s): " + ", ".join(missing))
    return {name: projects[name] for name in names}


def _ingest(forge_home: Path, project_names: list[str]) -> int:
    """Rebuild the task index for the given projects when TASKS.toml exists."""
    db_path = task_db_path(forge_home)
    board_paths = _board_project_paths(forge_home)
    db = WorldDatabase(db_path)
    count = 0
    try:
        for name in project_names:
            project_dir = _project_dir(forge_home, name, board_paths)
            path = project_tasks_path(project_dir)
            if not path.exists():
                continue
            db.ingest_project(
                project_path=project_dir,
                project_name=name,
                column_name=None,
                project_tasks=load_project_tasks(path),
                tasks_path=path,
            )
            count += 1
        db.conn.commit()
    finally:
        db.close()
    return count


def main() -> int:
    """Run the adapter command."""
    parser = argparse.ArgumentParser(description="Forge ↔ Super Productivity bridge")
    parser.add_argument("--forge-home", default=".")
    parser.add_argument("--config", type=Path)
    parser.add_argument("--json", action="store_true")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("setup-token", help="store the API token in macOS Keychain")
    sub.add_parser("status")
    sub.add_parser("list")
    show = sub.add_parser("show")
    show.add_argument("project")
    sub.add_parser("doctor")
    sub.add_parser("focus")
    start = sub.add_parser("start")
    start.add_argument("task_id")
    sub.add_parser("stop")
    align = sub.add_parser("align")
    align.add_argument("--apply", action="store_true")
    refresh = sub.add_parser("refresh")
    refresh.add_argument("--apply", action="store_true")
    refresh.add_argument("project", nargs="*")
    sync = sub.add_parser("sync")
    sync.add_argument("--apply", action="store_true")
    sync.add_argument("project", nargs="*")
    mirror = sub.add_parser("mirror-column", help="mirror kanban column tags onto SP tasks for a mapped project")
    mirror.add_argument("project")
    mirror.add_argument("column")
    mirror.add_argument("--tag", help="SP tag title to apply (defaults to Forge/<Column>)")
    mirror.add_argument(
        "--kanban-tag",
        action="append",
        default=[],
        dest="kanban_tags",
        help="Kanban tag titles to strip when switching columns (repeatable)",
    )
    menu_tree = sub.add_parser(
        "mirror-menu-tree",
        help="mirror Finder folder paths into SP sidebar project folders",
    )
    menu_tree.add_argument(
        "--dry-run",
        action="store_true",
        help="print planned tree only; do not write Super Productivity state",
    )
    menu_tree.add_argument(
        "--docs-root",
        type=Path,
        default=None,
        help="path root for nesting (default: ~/Documents)",
    )

    args = parser.parse_args()
    forge_home = Path(args.forge_home).expanduser().resolve()
    if args.command == "setup-token":
        keychain_token(prompt=True)
        print("Super Productivity token saved")
        return 0
    if args.command == "mirror-menu-tree":
        script = SCRIPT_DIR / "forge-sp-menu-tree.py"
        cmd = [sys.executable, str(script), "--forge-home", str(forge_home)]
        if args.dry_run:
            cmd.append("--dry-run")
        if args.docs_root is not None:
            cmd.extend(["--docs-root", str(args.docs_root)])
        if args.json:
            cmd.append("--json")
        raise SystemExit(subprocess.call(cmd))

    config = config_from_file(args.config or forge_home / "config.yaml")
    if args.command == "status":
        token_present = bool(keychain_token())
        health = None
        health_error = None
        try:
            health = SuperProductivityClient(config, keychain_token()).health()
        except SuperProductivityError as exc:
            health_error = str(exc)
        result = {
            "enabled": config.enabled,
            "endpoint": config.endpoint,
            "mapped_projects": config.mapped_projects,
            "token": token_present,
            "health": health,
            "health_error": health_error,
            "ledger": load_ledger(forge_home).get("updated_at"),
        }
        _print(result, args.json)
        return 0

    if not config.enabled:
        raise SuperProductivityError("superproductivity.enabled is false")
    client = SuperProductivityClient(config, keychain_token())

    if args.command == "list":
        result = client.projects()
        if args.json:
            print(json.dumps(result, indent=2))
        else:
            for project in result:
                print(f"{project.get('id') or project.get('_id')}  {project.get('title') or project.get('name')}")
        return 0

    if args.command == "show":
        project_id = (config.project_ids or {}).get(args.project)
        if not project_id:
            raise SuperProductivityError(f"unmapped project: {args.project}")
        tasks = client.tasks(project_id)
        ledger = load_ledger(forge_home)
        result = {
            "project": args.project,
            "project_id": project_id,
            "tasks": tasks,
            "ledger_tasks": {
                task_id: info
                for task_id, info in (ledger.get("tasks") or {}).items()
                if info.get("external_id")
            },
        }
        _print(result, args.json)
        return 0

    if args.command == "focus":
        _print(client.focus(), args.json)
        return 0
    if args.command == "start":
        _print(client.start_task(args.task_id), args.json)
        return 0
    if args.command == "stop":
        _print(client.stop_task(), args.json)
        return 0

    projects = config.project_ids or {}
    if args.command == "doctor":
        remote = {str(project.get("id") or project.get("_id")): project for project in client.projects()}
        board_paths = _board_project_paths(forge_home)
        findings = []
        for name, ident in projects.items():
            project_dir = _project_dir(forge_home, name, board_paths)
            findings.append({
                "project": name,
                "project_id": ident,
                "missing": ident not in remote,
                "folder_exists": project_dir.is_dir(),
                "folder": str(project_dir),
                "tasks_file": project_tasks_path(project_dir).exists(),
            })
        _print(findings, args.json)
        return 0

    if args.command == "align":
        remote = client.projects()
        names = {
            str(project.get("title") or project.get("name")): str(project.get("id") or project.get("_id"))
            for project in remote
        }
        proposals = []
        for name in projects:
            proposals.append({
                "project": name,
                "project_id": names.get(name) or projects.get(name),
                "action": "bind" if name in names else "manual-create",
                "configured_id": projects.get(name),
            })
        if args.apply:
            raise SuperProductivityError(
                "align --apply only previews bindings; set project_ids in config.yaml after creating projects in the app"
            )
        _print(proposals, args.json)
        return 0

    if args.command == "mirror-column":
        project_id = (config.project_ids or {}).get(args.project)
        if not project_id:
            raise SuperProductivityError(f"unmapped project: {args.project}")
        config_path = args.config or forge_home / "config.yaml"
        kanban_tags = list(args.kanban_tags or [])
        if not kanban_tags and config_path.exists():
            kanban_tags = list(board_column_tags_from_yaml(config_path.read_text(encoding="utf-8")).values())
        tag_title = args.tag
        if not tag_title and config_path.exists():
            tag_title = board_column_tags_from_yaml(config_path.read_text(encoding="utf-8")).get(args.column)
        result = mirror_column_tags(
            client,
            project_id=project_id,
            column=args.column,
            tag_title=tag_title,
            kanban_tag_titles=kanban_tags,
        )
        if args.json:
            print(json.dumps(result, indent=2, sort_keys=True))
        else:
            if result.get("ok"):
                print(f"SP column mirror: {result.get('tag')} on {result.get('updated')} task(s)")
            else:
                print(result.get("error") or "SP column mirror failed")
                return 1
        return 0 if result.get("ok") else 1

    selected = _selected_projects(config, getattr(args, "project", []) or [])
    if not selected:
        raise SuperProductivityError("no mapped projects configured under superproductivity.project_ids")

    board_paths = _board_project_paths(forge_home)
    with sync_lock(forge_home):
        ledger = load_ledger(forge_home)
        ledger["projects"] = dict(projects)
        outputs = []
        for name, ident in selected.items():
            project_dir = _project_dir(forge_home, name, board_paths)
            if args.command == "refresh":
                outputs.append(
                    refresh_project(
                        client=client,
                        project_id=ident,
                        project_name=name,
                        project_dir=project_dir,
                        apply=args.apply,
                    )
                )
            else:
                outputs.append(
                    sync_project(
                        client=client,
                        project_id=ident,
                        project_name=name,
                        project_dir=project_dir,
                        ledger=ledger,
                        apply=args.apply,
                    )
                )
        if args.apply:
            save_ledger(forge_home, ledger)
            ingested = _ingest(forge_home, list(selected))
            for item in outputs:
                item["ingested"] = ingested
        _print(outputs, args.json)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SuperProductivityError as exc:
        print(f"forge superproductivity: {exc}", file=sys.stderr)
        raise SystemExit(2)

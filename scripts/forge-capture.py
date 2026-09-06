#!/usr/bin/env python3
"""Forge GTD capture — inbox write/read against Super Productivity (or legacy tasks.db)."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from forge_tasks_world.capture import (  # noqa: E402
    CaptureStore,
    sniff_clipboard_link,
    task_db_path,
)
from forge_tasks_world.context_capture import resolve_captures  # noqa: E402
from forge_tasks_world.superproductivity import (  # noqa: E402
    SpTaskStore,
    SuperProductivityError,
    config_from_file,
)


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


def sp_enabled(forge_home: Path) -> bool:
    """Return True when Super Productivity is the configured task store."""
    return config_from_file(forge_home / "config.yaml").enabled


def open_store(forge_home: Path):
    """Return SpTaskStore when SP is enabled, otherwise legacy CaptureStore."""
    if sp_enabled(forge_home):
        return SpTaskStore(forge_home), "super-productivity"
    return CaptureStore(forge_home), "tasks.db"


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


def match_project(projects: list[dict], needle: str) -> dict:
    """Return a unique board project matching the name substring."""
    matches = [project for project in projects if needle.lower() in project["name"].lower()]
    if not matches:
        raise SystemExit(f"No project matching '{needle}'")
    if len(matches) > 1:
        names = ", ".join(project["name"] for project in matches[:8])
        raise SystemExit(f"Ambiguous project '{needle}': {names}")
    return matches[0]


def cmd_capture(args: argparse.Namespace) -> int:
    forge_home = Path(args.forge_home).expanduser()
    try:
        store, backend = open_store(forge_home)
    except SuperProductivityError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    try:
        link = args.link
        kind = args.kind
        if args.clipboard_link:
            paste = sys.stdin.read() if args.clipboard_link == "-" else args.clipboard_link
            sniffed = sniff_clipboard_link(paste)
            if sniffed and not link:
                kind, link = sniffed[0], sniffed[1]

        item = store.capture(
            args.title,
            link=link,
            kind=kind,
            note=args.note,
            file_path=Path(args.file) if args.file else None,
            stash=args.stash,
            source=args.source,
        )
    except (ValueError, FileNotFoundError, SuperProductivityError, KeyError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    finally:
        if hasattr(store, "close"):
            store.close()

    if args.json:
        payload = {
            "id": item.task_id,
            "title": item.title,
            "section": getattr(item, "section", "inbox"),
            "source": item.source,
            "links": item.links,
            "notes": item.notes,
            "created_at": item.created_at,
            "backend": backend,
        }
        if backend == "tasks.db":
            payload["db_path"] = str(task_db_path(forge_home))
        print(json.dumps(payload, indent=2))
    else:
        link_note = ""
        if item.links:
            first = item.links[0]
            link_note = f"  [{first['kind']}] {first['uri']}"
        print(f"Captured {item.task_id}: {item.title}{link_note}")
    return 0


def cmd_inbox(args: argparse.Namespace) -> int:
    forge_home = Path(args.forge_home).expanduser()
    try:
        store, _backend = open_store(forge_home)
    except SuperProductivityError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    try:
        items = store.list_inbox()
    except SuperProductivityError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    finally:
        if hasattr(store, "close"):
            store.close()

    if args.json:
        print(
            json.dumps(
                [
                    {
                        "id": item.task_id,
                        "title": item.title,
                        "source": item.source,
                        "created_at": item.created_at,
                        "notes": item.notes,
                        "links": item.links,
                    }
                    for item in items
                ],
                indent=2,
            )
        )
        return 0

    if not items:
        print("Inbox empty.")
        return 0

    print(f"Inbox ({len(items)})\n")
    for item in items:
        meta = []
        if item.source:
            meta.append(item.source)
        if item.created_at:
            meta.append(item.created_at[:10])
        suffix = f"  ·  {' · '.join(meta)}" if meta else ""
        print(f"  ☐ {item.title}{suffix}  ({item.task_id})")
        for link in item.links:
            print(f"      [{link.get('kind', 'link')}] {link.get('uri', '')}")
        if item.notes:
            for line in item.notes.splitlines()[:3]:
                print(f"      {line}")
    return 0


def cmd_assign(args: argparse.Namespace) -> int:
    forge_home = Path(args.forge_home).expanduser()
    projects = load_board_projects(forge_home)
    project = match_project(projects, args.project)
    try:
        store, backend = open_store(forge_home)
    except SuperProductivityError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    try:
        if backend == "super-productivity":
            store.assign(args.task_id, project["name"])
        else:
            store.assign(
                args.task_id,
                Path(project["path"]),
                project["name"],
                section=args.section,
                column_name=project.get("column"),
            )
    except (KeyError, SuperProductivityError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    finally:
        if hasattr(store, "close"):
            store.close()
    print(f"Assigned {args.task_id} → {project['name']} [{args.section}]")
    return 0


def cmd_complete(args: argparse.Namespace) -> int:
    forge_home = Path(args.forge_home).expanduser()
    try:
        store, _backend = open_store(forge_home)
    except SuperProductivityError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    try:
        store.complete(args.task_id)
    except (KeyError, SuperProductivityError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    finally:
        if hasattr(store, "close"):
            store.close()
    print(f"Completed {args.task_id}")
    return 0


def cmd_open(args: argparse.Namespace) -> int:
    forge_home = Path(args.forge_home).expanduser()
    try:
        store, _backend = open_store(forge_home)
    except SuperProductivityError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    try:
        uri = store.get_open_link(args.task_id)
    except SuperProductivityError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    finally:
        if hasattr(store, "close"):
            store.close()
    if not uri:
        print(f"No link on task {args.task_id}", file=sys.stderr)
        return 1
    if args.print_only:
        print(uri)
        return 0
    result = subprocess.run(["open", uri], check=False)
    return result.returncode


def cmd_service(args: argparse.Namespace) -> int:
    """Capture from a macOS Service or portable ``--context`` CLI."""
    forge_home = Path(args.forge_home).expanduser()
    try:
        store, _backend = open_store(forge_home)
    except SuperProductivityError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    files = [Path(path).expanduser() for path in (args.file or [])]
    prefer = (getattr(args, "prefer", None) or "auto").strip().lower()
    if args.mail and prefer == "auto":
        prefer = "mail"

    captured: list[dict] = []
    try:
        resolved = resolve_captures(files=files, text=args.text, prefer=prefer)
        for item in resolved:
            captured_item = store.capture(
                item.title,
                link=item.link,
                kind=item.kind,
                note=item.note,
                file_path=Path(item.file_path) if item.file_path else None,
                stash=args.stash,
                source=args.source,
            )
            captured.append(
                {
                    "id": captured_item.task_id,
                    "title": captured_item.title,
                    "strategy": item.strategy,
                }
            )
    except (ValueError, FileNotFoundError, SuperProductivityError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    finally:
        if hasattr(store, "close"):
            store.close()

    if not captured:
        print("Nothing to capture.", file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps({"captured": captured}, indent=2))
    else:
        for item in captured:
            strategy = item.get("strategy")
            suffix = f" [{strategy}]" if strategy else ""
            print(f"Captured {item['id']}: {item['title']}{suffix}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Forge capture — zero-friction inbox (Super Productivity when enabled).",
    )
    parser.add_argument(
        "--forge-home",
        default=str(resolve_forge_home()),
        help="Forge home directory (default: auto-detected)",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    capture = sub.add_parser("capture", help="Capture into the inbox")
    capture.add_argument("title", help="Inbox item title")
    capture.add_argument("--link", help="URI (message://, file://, https://, …)")
    capture.add_argument(
        "--kind",
        choices=["mail", "file", "url", "note", "obsidian", "bookends", "other"],
        help="Link kind (inferred when omitted)",
    )
    capture.add_argument("--note", help="Optional note body")
    capture.add_argument("--file", help="Local file path (link-only unless --stash)")
    capture.add_argument(
        "--stash",
        action="store_true",
        help="Copy --file into .forge/inbox/<id>/ (default: link only)",
    )
    capture.add_argument(
        "--source",
        default="cli",
        help="Capture source label (cli, menubar, assistant, …)",
    )
    capture.add_argument(
        "--clipboard-link",
        help="Optional clipboard text to sniff for a URI (use - for stdin)",
    )
    capture.add_argument("--json", action="store_true", help="Emit JSON")
    capture.set_defaults(func=cmd_capture)

    inbox = sub.add_parser("inbox", help="List inbox items")
    inbox.add_argument("--json", action="store_true", help="Emit JSON")
    inbox.set_defaults(func=cmd_inbox)

    assign = sub.add_parser("assign", help="Assign inbox item to a project")
    assign.add_argument("task_id", help="Task id")
    assign.add_argument("project", help="Project name substring")
    assign.add_argument(
        "--section",
        default="next",
        choices=["next", "waiting", "someday"],
        help="Legacy TASKS.toml section (ignored for Super Productivity)",
    )
    assign.set_defaults(func=cmd_assign)

    complete = sub.add_parser("complete", help="Mark a task done")
    complete.add_argument("task_id", help="Task id")
    complete.set_defaults(func=cmd_complete)

    open_cmd = sub.add_parser("open", help="Open the first link on a task")
    open_cmd.add_argument("task_id", help="Task id")
    open_cmd.add_argument(
        "--print-only",
        action="store_true",
        help="Print URI instead of opening",
    )
    open_cmd.set_defaults(func=cmd_open)

    service = sub.add_parser(
        "service",
        help="Context capture: files / Mail / browser URL / text (macOS Service + Linux CLI)",
    )
    service.add_argument("--text", help="Selected text (becomes note when a richer primary exists)")
    service.add_argument("--title", help="Unused with context resolver; kept for compatibility")
    service.add_argument("--file", action="append", default=[], help="File path (repeatable)")
    service.add_argument(
        "--mail",
        action="store_true",
        help="Prefer Mail selection (same as --prefer mail)",
    )
    service.add_argument(
        "--prefer",
        choices=["auto", "mail", "file", "browser", "text"],
        default="auto",
        help="Capture strategy (default: auto from frontmost app on macOS)",
    )
    service.add_argument("--stash", action="store_true", help="Copy files into .forge/inbox/")
    service.add_argument("--source", default="service")
    service.add_argument("--json", action="store_true")
    service.set_defaults(func=cmd_service)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())

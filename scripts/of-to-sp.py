#!/usr/bin/env python3
"""One-shot OmniFocus → Super Productivity import (dry-run by default).

Pending OF tasks map to:

- Forge-linked / aliased folders that already have ``project_ids`` (or an SP
  project with the same title)
- Otherwise the OmniFocus project or Single Action List name (create that SP
  project first via the generated plugin zip)
- True Inbox (no containing project) → Super Productivity Inbox

Identity marker in SP notes: ``[forge:of-id:<omnifocus-id>]``.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import shutil
import sys
import zipfile
from collections import Counter, defaultdict
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from forge_tasks_world.capture import format_sp_note_attachment, normalize_mail_uri  # noqa: E402
from forge_tasks_world.of_mapping import (  # noqa: E402
    PROJECT_FOLDER_ALIASES,
    keep_task,
    resolve_folder,
)
from forge_tasks_world.superproductivity import (  # noqa: E402
    INBOX_PROJECT_ID,
    SuperProductivityError,
    _created_task_id,
    _due_payload,
    _planned_to_ms,
    config_from_file,
    open_client,
    refuse_of_import_while_primary,
)


def _load_sync_of() -> Any:
    """Load ``sync-of-tasks-from-of.py`` (hyphenated filename)."""
    path = SCRIPT_DIR / "sync-of-tasks-from-of.py"
    spec = importlib.util.spec_from_file_location("sync_of_tasks_from_of", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_sync_of = _load_sync_of()
export_omnifocus = _sync_of.export_omnifocus
fmt_date = _sync_of.fmt_date
load_forge_board = _sync_of.load_forge_board
parse_message_link = _sync_of.parse_message_link
resolve_forge_home = _sync_of.resolve_forge_home

OF_ID_MARKER_RE = re.compile(r"\[forge:of-id:([^\]]+)\]")
PLUGIN_DIR = SCRIPT_DIR / "sp-plugins" / "of-bulk-projects"
PLUGIN_ZIP = SCRIPT_DIR / "sp-plugins" / "of-bulk-projects.zip"


@dataclass
class PlannedRow:
    """One pending OmniFocus task planned for Super Productivity."""

    of_id: str
    title: str
    of_project: str | None
    forge_folder: str | None
    destination: str
    project_id: str | None
    needs_project: bool
    due: str | None
    planned: str | None
    notes: str | None
    action: str
    reason: str | None = None


def of_id_marker(of_id: str) -> str:
    """Return the OmniFocus identity marker stored in SP notes."""
    return f"[forge:of-id:{of_id}]"


def build_user_notes(
    task: dict[str, Any],
    *,
    forge_home: Path | None = None,
) -> str | None:
    """Build user-visible notes (mail links as SP-safe ``file://`` trampolines)."""
    note = (task.get("note") or "").strip()
    parts: list[str] = ["[forge:source:omnifocus]"]
    message = parse_message_link(note) if note else None
    if note and not message:
        parts.append(note)
    elif note and message:
        cleaned = re.sub(r"<message:[^>]+>", "", note).strip()
        if cleaned:
            parts.append(cleaned)
        parts.extend(
            format_sp_note_attachment(
                normalize_mail_uri(message),
                kind="mail",
                forge_home=forge_home,
            )
        )
    elif message:
        parts.extend(
            format_sp_note_attachment(
                normalize_mail_uri(message),
                kind="mail",
                forge_home=forge_home,
            )
        )
    return "\n".join(parts)
def combine_of_notes(user_notes: str | None, of_id: str) -> str:
    """Attach the OmniFocus identity marker to notes."""
    marker = of_id_marker(of_id)
    if user_notes:
        return f"{user_notes.rstrip()}\n\n{marker}"
    return marker


def sp_title_index(projects: list[dict[str, Any]]) -> dict[str, str]:
    """Map SP project title → id (first wins on duplicates)."""
    out: dict[str, str] = {}
    for project in projects:
        title = (project.get("title") or "").strip()
        pid = project.get("id")
        if title and pid and title not in out:
            out[title] = str(pid)
    return out


def collect_existing_of_ids(client: Any, project_ids: list[str]) -> set[str]:
    """Scan SP notes for previously imported OmniFocus ids."""
    found: set[str] = set()
    targets = list(dict.fromkeys([*project_ids, INBOX_PROJECT_ID]))
    for project_id in targets:
        try:
            tasks = client.tasks(project_id, include_done=True)
        except SuperProductivityError:
            continue
        for task in tasks:
            notes = task.get("notes") or task.get("note") or ""
            match = OF_ID_MARKER_RE.search(str(notes))
            if match:
                found.add(match.group(1))
    return found


def resolve_destination(
    task: dict[str, Any],
    *,
    project_forge: dict[str, str | None],
    forge_paths: dict[str, Path],
    project_ids: dict[str, str],
    sp_by_title: dict[str, str],
) -> tuple[str, str | None, bool]:
    """Return (destination label, SP project id or None, needs_new_project)."""
    folder = resolve_folder(task, project_forge, forge_paths)
    if folder:
        if folder in project_ids:
            return folder, project_ids[folder], False
        if folder in sp_by_title:
            return folder, sp_by_title[folder], False
        # Forge-linked name with no SP project yet — create under that title.
        return folder, None, True

    of_project = (task.get("ofProjectName") or "").strip() or None
    if of_project:
        alias = PROJECT_FOLDER_ALIASES.get(of_project)
        if alias:
            if alias in project_ids:
                return alias, project_ids[alias], False
            if alias in sp_by_title:
                return alias, sp_by_title[alias], False
            return alias, None, True
        if of_project in project_ids:
            return of_project, project_ids[of_project], False
        if of_project in sp_by_title:
            return of_project, sp_by_title[of_project], False
        return of_project, None, True

    return "Inbox", INBOX_PROJECT_ID, False


def plan_import(
    of_data: dict[str, Any],
    *,
    forge_paths: dict[str, Path],
    project_ids: dict[str, str],
    sp_by_title: dict[str, str],
    existing_of_ids: set[str],
    forge_home: Path | None = None,
) -> list[PlannedRow]:
    """Build the dry-run / apply plan for pending OmniFocus tasks."""
    project_forge = {
        project["name"]: project.get("forgeFolder") for project in of_data.get("projects") or []
    }
    of_project_ids = {project["id"] for project in of_data.get("projects") or []}
    rows: list[PlannedRow] = []

    for task in of_data.get("tasks") or []:
        if task.get("completed"):
            continue
        if not keep_task(task, of_project_ids):
            continue
        of_id = str(task.get("id") or "").strip()
        title = (task.get("name") or "").strip().replace("\n", " ")
        if not of_id or not title:
            continue

        destination, project_id, needs_project = resolve_destination(
            task,
            project_forge=project_forge,
            forge_paths=forge_paths,
            project_ids=project_ids,
            sp_by_title=sp_by_title,
        )
        due = fmt_date(task.get("due"))
        planned = fmt_date(task.get("planned"))
        notes = build_user_notes(task, forge_home=forge_home)
        forge_folder = task.get("forgeFolder") or resolve_folder(task, project_forge, forge_paths)
        of_project = (task.get("ofProjectName") or "").strip() or None

        if of_id in existing_of_ids:
            rows.append(
                PlannedRow(
                    of_id=of_id,
                    title=title,
                    of_project=of_project,
                    forge_folder=forge_folder,
                    destination=destination,
                    project_id=project_id,
                    needs_project=False,
                    due=due,
                    planned=planned,
                    notes=notes,
                    action="skip",
                    reason="already imported",
                )
            )
            continue

        if needs_project and project_id is None:
            action = "blocked"  # until plugin creates the SP project
            reason = "SP project missing (create via of-bulk-projects.zip)"
        else:
            action = "create"
            reason = None

        rows.append(
            PlannedRow(
                of_id=of_id,
                title=title,
                of_project=of_project,
                forge_folder=forge_folder,
                destination=destination,
                project_id=project_id,
                needs_project=needs_project,
                due=due,
                planned=planned,
                notes=notes,
                action=action,
                reason=reason,
            )
        )
    return rows


def write_of_bulk_plugin(titles: list[str]) -> Path:
    """Write a one-shot plugin zip that creates missing OF project titles in SP."""
    PLUGIN_DIR.mkdir(parents=True, exist_ok=True)
    titles_js = json.dumps(titles, ensure_ascii=False, indent=2)
    plugin_js = f"""// Forge one-shot: create SP projects for OmniFocus project/SAL names.
const TITLES = {titles_js};

async function alreadyDone() {{
  try {{
    const raw = await PluginAPI.loadSyncedData();
    if (!raw) return false;
    const parsed = JSON.parse(raw);
    return Boolean(parsed && parsed.completedAt);
  }} catch (e) {{
    return false;
  }}
}}

async function run() {{
  if (await alreadyDone()) {{
    console.log('of-bulk-projects: already completed; skip');
    return;
  }}
  const existing = await PluginAPI.getAllProjects();
  const have = new Set((existing || []).map((p) => p.title));
  let created = 0;
  let skipped = 0;
  const errors = [];
  for (const title of TITLES) {{
    if (have.has(title)) {{
      skipped += 1;
      continue;
    }}
    try {{
      await PluginAPI.addProject({{ title }});
      have.add(title);
      created += 1;
    }} catch (err) {{
      errors.push(title + ': ' + (err && err.message ? err.message : String(err)));
    }}
  }}
  await PluginAPI.persistDataSynced(
    JSON.stringify({{
      completedAt: new Date().toISOString(),
      created,
      skipped,
      errors,
    }}),
  );
  const msg =
    'OF→SP: created ' +
    created +
    ' project(s), skipped ' +
    skipped +
    (errors.length ? ', errors ' + errors.length : '');
  console.log(msg, errors);
  PluginAPI.showSnack({{
    msg,
    type: errors.length ? 'ERROR' : 'SUCCESS',
  }});
}}

run().catch((err) => {{
  console.error('of-bulk-projects failed', err);
  PluginAPI.showSnack({{
    msg: 'OF bulk projects failed: ' + (err && err.message ? err.message : String(err)),
    type: 'ERROR',
  }});
}});
"""
    (PLUGIN_DIR / "plugin.js").write_text(plugin_js, encoding="utf-8")
    manifest = {
        "id": "of-bulk-projects",
        "name": "OF Bulk Projects",
        "version": "1.0.0",
        "manifestVersion": 1,
        "minSupVersion": "18.0.0",
        "description": "One-shot: create Super Productivity projects for OmniFocus project/SAL names.",
        "author": "Forge",
        "icon": "icon.svg",
        "permissions": [
            "getAllProjects",
            "addProject",
            "showSnack",
            "persistDataSynced",
            "loadSyncedData",
        ],
        "hooks": [],
    }
    (PLUGIN_DIR / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    for name in ("icon.svg", "icon.png"):
        src = SCRIPT_DIR / "sp-plugins" / "forge-bulk-projects" / name
        if src.is_file():
            shutil.copy2(src, PLUGIN_DIR / name)

    with zipfile.ZipFile(PLUGIN_ZIP, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.write(PLUGIN_DIR / "manifest.json", "manifest.json")
        archive.write(PLUGIN_DIR / "plugin.js", "plugin.js")
        for name in ("icon.svg", "icon.png"):
            path = PLUGIN_DIR / name
            if path.is_file():
                archive.write(path, name)
    return PLUGIN_ZIP


def create_sp_task(client: Any, row: PlannedRow) -> str:
    """Create one Super Productivity task from a planned row."""
    if not row.project_id:
        raise SuperProductivityError(f"missing project id for {row.title!r}")
    payload: dict[str, Any] = {
        "title": row.title,
        "notes": combine_of_notes(row.notes, row.of_id),
        "isDone": False,
    }
    if row.due:
        payload.update({k: v for k, v in _due_payload(row.due).items() if v is not None})
    if row.planned:
        planned_ms = _planned_to_ms(row.planned)
        if planned_ms is not None:
            payload["plannedAt"] = planned_ms
    created = client.create_task(row.project_id, payload)
    return _created_task_id(created)


def summarise(rows: list[PlannedRow]) -> dict[str, Any]:
    """Return aggregate counts for the plan."""
    counts = Counter(row.action for row in rows)
    by_dest: dict[str, int] = defaultdict(int)
    needs_projects = sorted({row.destination for row in rows if row.needs_project and row.action != "skip"})
    inbox = sum(1 for row in rows if row.destination == "Inbox" and row.action == "create")
    for row in rows:
        if row.action in ("create", "blocked"):
            by_dest[row.destination] += 1
    return {
        "pending_considered": len(rows),
        "actions": dict(counts),
        "inbox_creates": inbox,
        "projects_to_create": needs_projects,
        "projects_to_create_count": len(needs_projects),
        "by_destination": dict(sorted(by_dest.items(), key=lambda item: (-item[1], item[0]))),
    }


def print_human(summary: dict[str, Any], rows: list[PlannedRow], *, limit: int) -> None:
    """Print a compact human summary to stdout."""
    print("## OF → SP plan")
    print(f"pending considered: {summary['pending_considered']}")
    print(f"actions: {summary['actions']}")
    print(f"true Inbox → SP Inbox creates: {summary['inbox_creates']}")
    print(f"SP projects to create: {summary['projects_to_create_count']}")
    for title in summary["projects_to_create"][:40]:
        print(f"  - {title}")
    if summary["projects_to_create_count"] > 40:
        print(f"  … and {summary['projects_to_create_count'] - 40} more")
    print("\nTop destinations (create/blocked):")
    for dest, count in list(summary["by_destination"].items())[:20]:
        print(f"  {count:4d}  {dest}")
    print(f"\nSample rows (up to {limit}):")
    for row in rows[:limit]:
        flag = "NEW-PROJ" if row.needs_project else ("INBOX" if row.destination == "Inbox" else "mapped")
        print(f"  [{row.action:7}] {flag:8} → {row.destination} | {row.title[:60]}")


def main() -> int:
    """CLI entry: dry-run plan, optional plugin zip, optional --apply."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--forge-home",
        type=Path,
        default=None,
        help="Forge home (default: resolve from config.yaml)",
    )
    parser.add_argument("--json", action="store_true", help="Emit full JSON plan")
    parser.add_argument("--limit", type=int, default=30, help="Sample rows in human output")
    parser.add_argument(
        "--write-plugin",
        action="store_true",
        help="Write of-bulk-projects.zip for missing OF project/SAL titles",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Create SP tasks for destinations that already exist (not dry-run)",
    )
    parser.add_argument(
        "--allow-while-primary",
        action="store_true",
        help="Allow --apply even when superproductivity.primary is true",
    )
    parser.add_argument(
        "--skip-scan",
        action="store_true",
        help="Do not scan SP for existing [forge:of-id:…] markers (faster, risk of duplicates)",
    )
    args = parser.parse_args()

    forge_home = (args.forge_home or resolve_forge_home()).expanduser().resolve()
    config = config_from_file(forge_home / "config.yaml")
    if not config.enabled:
        print("superproductivity.enabled is false", file=sys.stderr)
        return 1
    if args.apply:
        refuse_of_import_while_primary(
            config,
            allow=args.allow_while_primary,
            action="of-to-sp --apply",
        )

    print("Exporting OmniFocus…", file=sys.stderr)
    of_data = export_omnifocus()
    forge_paths, _columns = load_forge_board(forge_home)
    client = open_client(forge_home)
    sp_projects = client.projects()
    sp_by_title = sp_title_index(sp_projects)

    existing: set[str] = set()
    if not args.skip_scan:
        print("Scanning SP for prior OF imports…", file=sys.stderr)
        existing = collect_existing_of_ids(
            client, list({*config.project_ids.values(), *sp_by_title.values()})
        )

    rows = plan_import(
        of_data,
        forge_paths=forge_paths,
        project_ids=dict(config.project_ids),
        sp_by_title=sp_by_title,
        existing_of_ids=existing,
        forge_home=forge_home,
    )
    summary = summarise(rows)

    plugin_path: str | None = None
    if args.write_plugin or summary["projects_to_create"]:
        if args.write_plugin or not args.apply:
            path = write_of_bulk_plugin(summary["projects_to_create"])
            plugin_path = str(path)
            print(f"plugin zip: {path}", file=sys.stderr)

    applied: list[dict[str, Any]] = []
    failed: list[dict[str, Any]] = []
    if args.apply:
        creatable = [row for row in rows if row.action == "create" and row.project_id]
        blocked = [row for row in rows if row.action == "blocked"]
        if blocked:
            print(
                f"warning: {len(blocked)} task(s) blocked until SP projects exist; "
                f"upload {PLUGIN_ZIP.name} then re-run --apply",
                file=sys.stderr,
            )
        print(f"Creating {len(creatable)} task(s)…", file=sys.stderr)
        for row in creatable:
            try:
                sp_id = create_sp_task(client, row)
                applied.append({"of_id": row.of_id, "sp_id": sp_id, "destination": row.destination})
            except (SuperProductivityError, ValueError) as exc:
                failed.append({"of_id": row.of_id, "title": row.title, "error": str(exc)})
                print(f"failed: {row.title}: {exc}", file=sys.stderr)

    result = {
        "ok": not failed,
        "dry_run": not args.apply,
        "forge_home": str(forge_home),
        "summary": summary,
        "plugin_zip": plugin_path,
        "applied": applied,
        "failed": failed,
        "generated_at": datetime.now().astimezone().isoformat(),
        "rows": [asdict(row) for row in rows] if args.json else None,
    }
    if args.json:
        if result["rows"] is None:
            result["rows"] = [asdict(row) for row in rows]
        print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        print_human(summary, rows, limit=args.limit)
        if args.apply:
            print(f"\napplied: {len(applied)}  failed: {len(failed)}  blocked: {summary['actions'].get('blocked', 0)}")
        else:
            print(
                "\nDry-run only. Next:\n"
                f"  1. Upload {PLUGIN_ZIP} in SP → Settings → Plugins (if projects_to_create > 0)\n"
                "  2. Re-run this script (no --apply) to confirm blocked → create\n"
                "  3. python3 scripts/of-to-sp.py --apply"
            )
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

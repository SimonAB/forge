#!/usr/bin/env python3
"""One-shot OmniFocus → Super Productivity import (dry-run by default).

Destination titles follow ``forge_tasks_world.of_sp_destinations``:

- Finder / board folder spelling whenever an OF project maps there
- Otherwise the OmniFocus project / SAL title
- True Inbox (no containing project) → Super Productivity Inbox

Identity marker in SP notes: ``[forge:of-id:<omnifocus-id>]``.
Already-imported tasks in the wrong SP project are planned as ``rehome``.
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
from forge_tasks_world.of_mapping import keep_task, resolve_folder  # noqa: E402
from forge_tasks_world.of_sp_destinations import (  # noqa: E402
    build_sp_destination_map,
    destination_for_task,
    fold_title,
    lookup_sp_project_id,
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
    """Map SP project title → id (first wins; also index NFC-folded keys)."""
    out: dict[str, str] = {}
    for project in projects:
        title = (project.get("title") or "").strip()
        pid = project.get("id")
        if not title or not pid:
            continue
        ident = str(pid)
        if title not in out:
            out[title] = ident
        folded = fold_title(title)
        if folded not in out:
            out[folded] = ident
    return out


def collect_imported_tasks(
    client: Any, project_ids: list[str]
) -> dict[str, dict[str, str]]:
    """Map OmniFocus id → ``{sp_id, project_id}`` for tasks with OF markers."""
    found: dict[str, dict[str, str]] = {}
    targets = list(dict.fromkeys([*project_ids, INBOX_PROJECT_ID]))
    for project_id in targets:
        try:
            tasks = client.tasks(project_id, include_done=True)
        except SuperProductivityError:
            continue
        for task in tasks:
            notes = task.get("notes") or task.get("note") or ""
            match = OF_ID_MARKER_RE.search(str(notes))
            if not match:
                continue
            of_id = match.group(1)
            sp_id = str(task.get("id") or "").strip()
            if not sp_id:
                continue
            found[of_id] = {
                "sp_id": sp_id,
                "project_id": str(task.get("projectId") or project_id),
            }
    return found


def collect_existing_of_ids(client: Any, project_ids: list[str]) -> set[str]:
    """Scan SP notes for previously imported OmniFocus ids."""
    return set(collect_imported_tasks(client, project_ids))


def resolve_destination(
    task: dict[str, Any],
    *,
    dest_by_of_project: dict[str, str],
    forge_paths: dict[str, Path],
    project_ids: dict[str, str],
    sp_by_title: dict[str, str],
) -> tuple[str, str | None, bool]:
    """Return (destination label, SP project id or None, needs_new_project)."""
    destination = destination_for_task(
        task,
        dest_by_of_project=dest_by_of_project,
        forge_paths=forge_paths,
        sp_by_title=sp_by_title,
    )
    if destination == "Inbox":
        return "Inbox", INBOX_PROJECT_ID, False

    project_id = lookup_sp_project_id(
        destination, project_ids=project_ids, sp_by_title=sp_by_title
    )
    if project_id:
        return destination, project_id, False
    return destination, None, True


def plan_import(
    of_data: dict[str, Any],
    *,
    forge_paths: dict[str, Path],
    project_ids: dict[str, str],
    sp_by_title: dict[str, str],
    existing_of_ids: set[str],
    imported: dict[str, dict[str, str]] | None = None,
    forge_home: Path | None = None,
) -> list[PlannedRow]:
    """Build the dry-run / apply plan for pending OmniFocus tasks."""
    project_forge = {
        project["name"]: project.get("forgeFolder") for project in of_data.get("projects") or []
    }
    of_project_ids = {project["id"] for project in of_data.get("projects") or []}
    dest_by_of_project = build_sp_destination_map(of_data, forge_paths=forge_paths)
    imported = imported or {}
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
            dest_by_of_project=dest_by_of_project,
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
            prior = imported.get(of_id) or {}
            prior_project = prior.get("project_id")
            if needs_project and project_id is None:
                action = "rehome_blocked"
                reason = "already imported; create SP project then rehome"
            elif project_id and prior_project and prior_project != project_id:
                action = "rehome"
                reason = f"move from {prior_project} → {destination}"
            else:
                action = "skip"
                reason = "already imported"
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
            continue

        if needs_project and project_id is None:
            action = "blocked"
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
    """Write a one-shot plugin zip that creates missing SP project titles."""
    PLUGIN_DIR.mkdir(parents=True, exist_ok=True)
    titles_js = json.dumps(titles, ensure_ascii=False, indent=2)
    plugin_js = f"""// Forge: create missing SP projects (OF titles / Finder-aligned names).
// Idempotent by title — always creates any title still missing.
const TITLES = {titles_js};

async function run() {{
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
      titles: TITLES,
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
        "id": "of-bulk-projects-v2",
        "name": "OF Bulk Projects v2",
        "version": "2.0.0",
        "manifestVersion": 1,
        "minSupVersion": "18.0.0",
        "description": "Create Super Productivity projects for OF titles / Finder-aligned destinations.",
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


def rehome_sp_task(
    client: Any,
    *,
    of_id: str,
    imported: dict[str, dict[str, str]],
    project_id: str,
) -> str:
    """Move an already-imported SP task into ``project_id``; return SP task id."""
    prior = imported.get(of_id)
    if not prior:
        raise SuperProductivityError(f"no imported SP task for OF id {of_id}")
    sp_id = prior["sp_id"]
    client.update_task(sp_id, {"projectId": project_id})
    return sp_id


def summarise(rows: list[PlannedRow]) -> dict[str, Any]:
    """Return aggregate counts for the plan."""
    counts = Counter(row.action for row in rows)
    by_dest: dict[str, int] = defaultdict(int)
    needs_projects = sorted(
        {
            row.destination
            for row in rows
            if row.needs_project and row.action != "skip"
        }
    )
    inbox = sum(1 for row in rows if row.destination == "Inbox" and row.action == "create")
    for row in rows:
        if row.action in ("create", "blocked", "rehome", "rehome_blocked"):
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
    print("\nTop destinations (create/rehome/blocked):")
    for dest, count in list(summary["by_destination"].items())[:25]:
        print(f"  {count:4d}  {dest}")
    print(f"\nSample rows (up to {limit}):")
    for row in rows[:limit]:
        flag = "NEW-PROJ" if row.needs_project else ("INBOX" if row.destination == "Inbox" else "mapped")
        print(f"  [{row.action:14}] {flag:8} → {row.destination} | {row.title[:60]}")


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
        help="Write of-bulk-projects.zip for missing destination titles",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Create and rehome SP tasks for destinations that already exist",
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

    imported: dict[str, dict[str, str]] = {}
    existing: set[str] = set()
    if not args.skip_scan:
        print("Scanning SP for prior OF imports…", file=sys.stderr)
        imported = collect_imported_tasks(
            client, list({*config.project_ids.values(), *sp_by_title.values()})
        )
        existing = set(imported)

    rows = plan_import(
        of_data,
        forge_paths=forge_paths,
        project_ids=dict(config.project_ids),
        sp_by_title=sp_by_title,
        existing_of_ids=existing,
        imported=imported,
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
    rehoused: list[dict[str, Any]] = []
    failed: list[dict[str, Any]] = []
    if args.apply:
        creatable = [row for row in rows if row.action == "create" and row.project_id]
        rehome_rows = [row for row in rows if row.action == "rehome" and row.project_id]
        blocked = [row for row in rows if row.action in ("blocked", "rehome_blocked")]
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
        print(f"Rehoming {len(rehome_rows)} task(s)…", file=sys.stderr)
        for row in rehome_rows:
            try:
                sp_id = rehome_sp_task(
                    client,
                    of_id=row.of_id,
                    imported=imported,
                    project_id=row.project_id or "",
                )
                rehoused.append(
                    {"of_id": row.of_id, "sp_id": sp_id, "destination": row.destination}
                )
            except (SuperProductivityError, ValueError) as exc:
                failed.append({"of_id": row.of_id, "title": row.title, "error": str(exc)})
                print(f"rehome failed: {row.title}: {exc}", file=sys.stderr)

    result = {
        "ok": not failed,
        "dry_run": not args.apply,
        "forge_home": str(forge_home),
        "summary": summary,
        "plugin_zip": plugin_path,
        "applied": applied,
        "rehoused": rehoused,
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
            print(
                f"\napplied creates={len(applied)} rehomes={len(rehoused)} "
                f"failed={len(failed)} blocked={summary['actions'].get('blocked', 0) + summary['actions'].get('rehome_blocked', 0)}"
            )
        else:
            print(
                "\nDry-run only. Next:\n"
                f"  1. Upload {PLUGIN_ZIP} in SP → Settings → Plugins (if projects_to_create > 0)\n"
                "  2. Re-run this script (no --apply) to confirm blocked → create/rehome\n"
                "  3. python3 scripts/of-to-sp.py --apply --allow-while-primary"
            )
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

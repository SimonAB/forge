#!/usr/bin/env python3
"""Rationalise duplicate Super Productivity projects toward Finder names.

Rehomes open tasks from OF-titled / alias SP projects into the preferred
Finder / board folder title, then reports empty sources to archive in the UI
(Local REST cannot delete projects).

Dry-run by default; pass ``--apply`` to PATCH ``projectId`` on tasks.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
import zipfile
from collections import defaultdict
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from forge_tasks_world.of_mapping import fold_title  # noqa: E402
from forge_tasks_world.superproductivity import (  # noqa: E402
    SuperProductivityError,
    config_from_file,
    open_client,
)

# Source SP title → preferred Finder / board SP title.
MERGE_INTO_FINDER: dict[str, str] = {
    "PGT – Fundamentals of Programming": "2. Fundamentals of Programming",
    "PGT – Modern Inference": "3. Modern Inference",
    "PGT - QMBCE/DSEE": "0. DSEE Admin",
    "PGT – Intro to R": "PGT",
    "Viral Host Predictor v2": "Viruses-ViralHostPredictor",
    "VectorPredictor": "Viruses-ViralHostPredictor",
    "Mozzies - Open Philanthropy": "Mozzies Open Philanthropy",
    "Mozzies - AcMedSci GCRF networking grant": "Mozzies Open Philanthropy",
    "Mozzies-AI_MIRS_Royal_Society": "Mozzies-MIRS-AI_Gates Deep Surveillance",
    "Sunfish - NERC EOI": "ZebraFinches",
    "Zebrafinches transcriptomes NERC": "ZebraFinches",
    "Birds_light_at_night NERC": "ZebraFinches",
    "PDR": "Rivka Lim - PDRA",
    "PDRA — Rivka": "Rivka Lim - PDRA",
    "SLiMs model paper": "SLiMs_manuscript",
    "Wild Vaccines: submit Leverhulme proposal": "Apodemus - Wild Vaccines WT discovery",
    "Activate grant [Wellcome, Leverhulme, ERC] Application": "Apodemus - Wild Vaccines WT discovery",
}

PLUGIN_DIR = SCRIPT_DIR / "sp-plugins" / "forge-finder-projects"
PLUGIN_ZIP = SCRIPT_DIR / "sp-plugins" / "forge-finder-projects.zip"


def sp_index(projects: list[dict[str, Any]]) -> dict[str, str]:
    """Map title (and folded title) → project id."""
    out: dict[str, str] = {}
    for project in projects:
        title = (project.get("title") or "").strip()
        pid = project.get("id")
        if not title or not pid:
            continue
        ident = str(pid)
        out.setdefault(title, ident)
        out.setdefault(fold_title(title), ident)
    return out


def resolve_id(title: str, index: dict[str, str]) -> str | None:
    """Resolve SP id by exact or folded title."""
    return index.get(title) or index.get(fold_title(title))


def write_finder_plugin(titles: list[str]) -> Path:
    """Write a one-shot plugin that creates missing Finder-named SP projects."""
    PLUGIN_DIR.mkdir(parents=True, exist_ok=True)
    titles_js = json.dumps(titles, ensure_ascii=False, indent=2)
    plugin_js = f"""// Forge: create SP projects matching Finder / board folder titles.
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
    'Finder→SP: created ' +
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
  console.error('forge-finder-projects failed', err);
  PluginAPI.showSnack({{
    msg: 'Finder projects failed: ' + (err && err.message ? err.message : String(err)),
    type: 'ERROR',
  }});
}});
"""
    (PLUGIN_DIR / "plugin.js").write_text(plugin_js, encoding="utf-8")
    manifest = {
        "id": "forge-finder-projects",
        "name": "Forge Finder Projects",
        "version": "1.0.0",
        "manifestVersion": 1,
        "minSupVersion": "18.0.0",
        "description": "Create Super Productivity projects titled like Finder / board folders.",
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


def plan_merges(
    client: Any,
    *,
    board_names: set[str],
) -> dict[str, Any]:
    """Build rehome plan and missing Finder project titles."""
    projects = client.projects()
    index = sp_index(projects)
    by_title = {(p.get("title") or "").strip(): p for p in projects}

    missing_targets: set[str] = set()
    moves: list[dict[str, Any]] = []
    blocked: list[dict[str, Any]] = []
    already: list[str] = []

    # Ensure board folders that lack an SP project are requested.
    for name in sorted(board_names):
        if resolve_id(name, index) is None:
            missing_targets.add(name)

    for source, target in sorted(MERGE_INTO_FINDER.items()):
        src_id = resolve_id(source, index)
        if not src_id:
            continue
        tgt_id = resolve_id(target, index)
        if not tgt_id:
            missing_targets.add(target)
            blocked.append({"source": source, "target": target, "reason": "target missing"})
            continue
        if src_id == tgt_id:
            already.append(source)
            continue
        tasks = client.tasks(src_id, include_done=False)
        if not tasks:
            already.append(f"{source} (empty)")
            continue
        for task in tasks:
            tid = str(task.get("id") or "")
            if not tid:
                continue
            moves.append(
                {
                    "task_id": tid,
                    "title": task.get("title"),
                    "from": source,
                    "from_id": src_id,
                    "to": target,
                    "to_id": tgt_id,
                }
            )

    by_pair: dict[tuple[str, str], int] = defaultdict(int)
    for row in moves:
        by_pair[(row["from"], row["to"])] += 1

    return {
        "moves": moves,
        "blocked": blocked,
        "already": already,
        "missing_targets": sorted(missing_targets),
        "by_pair": {f"{a} → {b}": n for (a, b), n in sorted(by_pair.items(), key=lambda x: -x[1])},
        "empty_sources_after": [
            src
            for src in MERGE_INTO_FINDER
            if resolve_id(src, index)
            and resolve_id(MERGE_INTO_FINDER[src], index)
            and resolve_id(src, index) != resolve_id(MERGE_INTO_FINDER[src], index)
        ],
        "plugin_zip": None,
    }


def apply_moves(client: Any, moves: list[dict[str, Any]]) -> dict[str, Any]:
    """PATCH each task onto its Finder-named project."""
    ok: list[str] = []
    failed: list[dict[str, str]] = []
    for row in moves:
        try:
            client.update_task(row["task_id"], {"projectId": row["to_id"]})
            ok.append(row["task_id"])
        except (SuperProductivityError, ValueError) as exc:
            failed.append({"task_id": row["task_id"], "title": str(row.get("title")), "error": str(exc)})
    return {"moved": len(ok), "failed": failed}


def load_board_names(forge_home: Path) -> set[str]:
    """Return Finder / board project directory names."""
    import subprocess

    raw = subprocess.check_output(["forge", "board", "--json"], cwd=str(forge_home), text=True)
    data = json.loads(raw)
    return {(p.get("name") or "").strip() for p in data.get("projects") or [] if p.get("name")}


def main() -> int:
    """CLI entry for dry-run / apply rationalisation."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--forge-home", type=Path, default=None)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--write-plugin", action="store_true", default=True)
    args = parser.parse_args()

    forge_home = (args.forge_home or Path.cwd()).expanduser().resolve()
    config = config_from_file(forge_home / "config.yaml")
    if not config.enabled:
        print("superproductivity.enabled is false", file=sys.stderr)
        return 1

    client = open_client(forge_home)
    board_names = load_board_names(forge_home)
    plan = plan_merges(client, board_names=board_names)

    if args.write_plugin and plan["missing_targets"]:
        path = write_finder_plugin(plan["missing_targets"])
        plan["plugin_zip"] = str(path)
        print(f"plugin zip: {path}", file=sys.stderr)

    result: dict[str, Any] = {"ok": True, "dry_run": not args.apply, "plan": plan}
    if args.apply:
        if plan["blocked"]:
            print(
                f"warning: {len(plan['blocked'])} merge(s) blocked until Finder SP projects exist",
                file=sys.stderr,
            )
        applied = apply_moves(client, plan["moves"])
        result["applied"] = applied
        result["ok"] = not applied["failed"]
        print(
            f"moved={applied['moved']} failed={len(applied['failed'])}",
            file=sys.stderr,
        )

    if args.json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        print("## SP duplicate rationalisation (prefer Finder names)")
        print(f"moves ready: {len(plan['moves'])}")
        for pair, count in list(plan["by_pair"].items())[:30]:
            print(f"  {count:3d}  {pair}")
        print(f"blocked (missing target): {len(plan['blocked'])}")
        for row in plan["blocked"]:
            print(f"  - {row['source']} → {row['target']}")
        print(f"missing Finder SP projects: {len(plan['missing_targets'])}")
        for title in plan["missing_targets"][:40]:
            print(f"  - {title}")
        if plan.get("plugin_zip"):
            print(f"\nUpload plugin: {plan['plugin_zip']}")
            print("Then re-run with --apply")
        if args.apply:
            print("\nArchive empty OF-titled SP projects in the SP UI (REST cannot delete).")
            for src in plan["empty_sources_after"]:
                print(f"  - {src}")
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

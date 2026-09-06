#!/usr/bin/env python3
"""Build the one-shot Super Productivity plugin zip for Forge folder projects."""

from __future__ import annotations

import json
import subprocess
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLUGIN_DIR = Path(__file__).resolve().parent / "forge-bulk-projects"
ZIP_PATH = Path(__file__).resolve().parent / "forge-bulk-projects.zip"


def missing_titles(forge_home: Path) -> list[str]:
    """Return Forge board folder names that are not yet Super Productivity projects."""
    board = json.loads(
        subprocess.check_output(["forge", "board", "--json"], cwd=forge_home, text=True)
    )
    names = sorted({p["name"] for p in board.get("projects") or [] if p.get("name")})
    sp = json.loads(
        subprocess.check_output(
            [
                "python3",
                str(forge_home / "scripts" / "forge-superproductivity.py"),
                "--forge-home",
                str(forge_home),
                "--json",
                "list",
            ],
            text=True,
        )
    )
    have = {p.get("title") for p in sp if p.get("title")}
    return [name for name in names if name not in have]


def write_plugin_js(titles: list[str]) -> None:
    """Write plugin.js that creates each missing title via PluginAPI.addProject."""
    titles_js = json.dumps(titles, ensure_ascii=False, indent=2)
    plugin_js = f"""// Forge one-shot: create missing SP projects for Forge board folders.
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
    console.log('forge-bulk-projects: already completed; skip');
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
    'Forge: created ' +
    created +
    ' SP project(s), skipped ' +
    skipped +
    (errors.length ? ', errors ' + errors.length : '');
  console.log(msg, errors);
  PluginAPI.showSnack({{
    msg,
    type: errors.length ? 'ERROR' : 'SUCCESS',
  }});
}}

run().catch((err) => {{
  console.error('forge-bulk-projects failed', err);
  PluginAPI.showSnack({{
    msg: 'Forge bulk projects failed: ' + (err && err.message ? err.message : String(err)),
    type: 'ERROR',
  }});
}});
"""
    PLUGIN_DIR.mkdir(parents=True, exist_ok=True)
    (PLUGIN_DIR / "plugin.js").write_text(plugin_js, encoding="utf-8")


def build_zip() -> Path:
    """Zip manifest, icon, and plugin.js for Super Productivity Upload Plugin."""
    with zipfile.ZipFile(ZIP_PATH, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.write(PLUGIN_DIR / "manifest.json", "manifest.json")
        archive.write(PLUGIN_DIR / "plugin.js", "plugin.js")
        icon_svg = PLUGIN_DIR / "icon.svg"
        if icon_svg.is_file():
            archive.write(icon_svg, "icon.svg")
        icon_png = PLUGIN_DIR / "icon.png"
        if icon_png.is_file():
            archive.write(icon_png, "icon.png")
    return ZIP_PATH


def main() -> int:
    """Build the plugin for the current board."""
    titles = missing_titles(ROOT)
    write_plugin_js(titles)
    path = build_zip()
    print(f"titles={len(titles)}")
    print(f"zip={path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

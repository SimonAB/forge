#!/usr/bin/env python3
"""
Wire Forge's Hermes skill into a local Hermes + Ollama stack (privacy-first).

Idempotent: safe to run repeatedly. Modifies ~/.hermes/config.yaml only to append
the Forge skills directory to skills.external_dirs when missing.

Exit 0 when verification passes; non-zero otherwise.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Sequence


DEFAULT_FORGE_HOME = Path.home() / "Documents" / "Forge"
HERMES_CONFIG = Path.home() / ".hermes" / "config.yaml"
CURSOR_MCP = Path.home() / ".cursor" / "mcp.json"
OLLAMA_TAGS_URL = "http://127.0.0.1:11434/api/tags"
SKILL_NAME = "forge-board"


def resolve_forge_home(explicit: Path | None) -> Path:
    """Resolve Forge home from flag, FORGE_HOME, script location, or default."""

    if explicit is not None:
        return explicit.expanduser().resolve()
    env = os.environ.get("FORGE_HOME", "").strip()
    if env:
        return Path(env).expanduser().resolve()
    script_root = Path(__file__).resolve().parent.parent
    if (script_root / "config.yaml").exists() or (script_root / ".hermes" / "skills").is_dir():
        return script_root
    return DEFAULT_FORGE_HOME.expanduser().resolve()


def forge_skills_dir(forge_home: Path) -> Path:
    """Return the Hermes skills directory shipped with Forge."""

    return (forge_home / ".hermes" / "skills").resolve()


def which(name: str) -> Path | None:
    """Return the first executable on PATH, if any."""

    found = shutil.which(name)
    return Path(found) if found else None


def ollama_reachable() -> bool:
    """Return True when Ollama responds on loopback."""

    try:
        with urllib.request.urlopen(OLLAMA_TAGS_URL, timeout=3) as resp:
            return 200 <= resp.status < 300
    except (urllib.error.URLError, TimeoutError, OSError):
        return False


def read_external_dirs(config_text: str) -> list[str]:
    """Parse skills.external_dirs from Hermes config YAML (minimal parser)."""

    lines = config_text.splitlines()
    in_skills = False
    in_external = False
    dirs: list[str] = []
    for line in lines:
        stripped = line.strip()
        if not in_skills:
            if re.match(r"^skills:\s*$", stripped):
                in_skills = True
            continue
        if not in_external:
            if re.match(r"^external_dirs:\s*\[\s*\]\s*$", stripped):
                return []
            if re.match(r"^external_dirs:\s*$", stripped):
                in_external = True
                continue
            if re.match(r"^external_dirs:\s*\[", stripped):
                inline = stripped.split("[", 1)[1].split("]", 1)[0]
                for part in inline.split(","):
                    cleaned = part.strip().strip("'\"")
                    if cleaned:
                        dirs.append(cleaned)
                return dirs
            if stripped and not stripped.startswith("#") and not line.startswith(" "):
                break
            continue
        if stripped.startswith("- "):
            item = stripped[2:].strip().strip("'\"")
            if item:
                dirs.append(item)
            continue
        if stripped and not line.startswith(" "):
            break
        if stripped and not stripped.startswith("#"):
            break
    return dirs


def merge_external_dir(config_text: str, new_dir: str) -> tuple[str, bool]:
    """Append new_dir to skills.external_dirs when absent. Returns (text, changed)."""

    normalised = str(Path(new_dir).expanduser().resolve())
    existing = [str(Path(p).expanduser().resolve()) for p in read_external_dirs(config_text)]
    if normalised in existing:
        return config_text, False

    lines = config_text.splitlines()
    for idx, line in enumerate(lines):
        if re.match(r"^\s*external_dirs:\s*\[\s*\]\s*$", line):
            indent = re.match(r"^(\s*)", line).group(1)  # type: ignore[union-attr]
            lines[idx] = f"{indent}external_dirs:"
            lines.insert(idx + 1, f"{indent}  - {normalised}")
            return "\n".join(lines) + ("\n" if config_text.endswith("\n") else ""), True
        if re.match(r"^\s*external_dirs:\s*$", line):
            indent = re.match(r"^(\s*)", line).group(1)  # type: ignore[union-attr]
            insert_at = idx + 1
            while insert_at < len(lines) and (
                not lines[insert_at].strip() or lines[insert_at].lstrip().startswith("#")
            ):
                insert_at += 1
            lines.insert(insert_at, f"{indent}  - {normalised}")
            return "\n".join(lines) + ("\n" if config_text.endswith("\n") else ""), True

    # No skills block — append a minimal one.
    block = f"\nskills:\n  external_dirs:\n    - {normalised}\n"
    suffix = "" if config_text.endswith("\n") or not config_text else "\n"
    return config_text + suffix + block, True


def hermes_skill_visible() -> bool:
    """Return True when forge-board appears in hermes skills list."""

    hermes = which("hermes")
    if hermes is None:
        return False
    try:
        out = subprocess.check_output(
            [str(hermes), "skills", "list"],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=60,
        )
    except (subprocess.CalledProcessError, OSError, subprocess.TimeoutExpired):
        return False
    return SKILL_NAME in out


def write_cursor_mcp_sample(sample_path: Path, dry_run: bool) -> bool:
    """Write Cursor MCP config from sample when missing."""

    if CURSOR_MCP.exists():
        print(f"Cursor MCP already present: {CURSOR_MCP}")
        return True
    if not sample_path.is_file():
        print(f"Sample MCP config not found: {sample_path}", file=sys.stderr)
        return False
    payload = sample_path.read_text(encoding="utf-8")
    if dry_run:
        print(f"[dry-run] Would write {CURSOR_MCP}")
        return True
    CURSOR_MCP.parent.mkdir(parents=True, exist_ok=True)
    CURSOR_MCP.write_text(payload, encoding="utf-8")
    print(f"Wrote {CURSOR_MCP}")
    return True


def verify_checks() -> list[tuple[str, bool, str]]:
    """Run post-setup verification checks."""

    checks: list[tuple[str, bool, str]] = []
    checks.append(("Ollama reachable (loopback)", ollama_reachable(), OLLAMA_TAGS_URL))
    hermes = which("hermes")
    checks.append(
        (
            "Hermes on PATH",
            hermes is not None,
            str(hermes) if hermes else "install Hermes and ensure it is on PATH",
        )
    )
    forge = which("forge")
    checks.append(
        (
            "forge on PATH",
            forge is not None,
            str(forge) if forge else "Forge → Preferences → Install CLI…",
        )
    )
    skill_ok = hermes_skill_visible()
    checks.append(
        (
            f"Hermes skill '{SKILL_NAME}' visible",
            skill_ok,
            "run setup to add skills.external_dirs, then restart Hermes if needed",
        )
    )
    return checks


def print_checks(checks: Sequence[tuple[str, bool, str]]) -> bool:
    """Print checks and return whether all passed."""

    ok = True
    for label, passed, detail in checks:
        mark = "ok" if passed else "FAIL"
        print(f"  [{mark}] {label} — {detail}")
        ok = ok and passed
    return ok


def main(argv: list[str] | None = None) -> int:
    """Entry point."""

    parser = argparse.ArgumentParser(description="Set up Hermes + Forge (local, privacy-first).")
    parser.add_argument("--forge-home", type=Path, default=None, help="Forge directory (default: auto-detect)")
    parser.add_argument("--dry-run", action="store_true", help="Show actions without writing files")
    parser.add_argument("--skip-cursor-mcp", action="store_true", help="Do not create ~/.cursor/mcp.json")
    parser.add_argument("--verify-only", action="store_true", help="Only run verification checks")
    args = parser.parse_args(argv)

    forge_home = resolve_forge_home(args.forge_home)
    skills_dir = forge_skills_dir(forge_home)
    sample_mcp = forge_home / "packaging" / "hermes" / "cursor-mcp.sample.json"

    print("Forge Hermes setup (privacy-first, local Ollama)")
    print(f"  Forge home:     {forge_home}")
    print(f"  Skills dir:     {skills_dir}")
    print(f"  Hermes config:  {HERMES_CONFIG}")
    print()

    if not skills_dir.is_dir():
        print(f"ERROR: Forge skills directory not found: {skills_dir}", file=sys.stderr)
        return 1

    if args.verify_only:
        print("Verification:")
        return 0 if print_checks(verify_checks()) else 1

    if not ollama_reachable():
        print("WARNING: Ollama is not reachable at 127.0.0.1:11434 — start Ollama before using Hermes locally.")
    if which("hermes") is None:
        print("WARNING: hermes not on PATH — install Hermes first (https://hermes-agent.nousresearch.com/).")

    # Skill wiring
    if HERMES_CONFIG.is_file():
        original = HERMES_CONFIG.read_text(encoding="utf-8")
        merged, changed = merge_external_dir(original, str(skills_dir))
        if changed:
            if args.dry_run:
                print(f"[dry-run] Would update {HERMES_CONFIG} (add skills.external_dirs entry)")
            else:
                HERMES_CONFIG.write_text(merged, encoding="utf-8")
                print(f"Updated {HERMES_CONFIG} (added skills.external_dirs entry)")
        else:
            print(f"skills.external_dirs already includes {skills_dir}")
    else:
        msg = (
            f"WARNING: {HERMES_CONFIG} not found — run `hermes setup` first, "
            f"then re-run this script."
        )
        print(msg)

    if which("forge") is None:
        print("NOTE: forge is not on PATH — use Forge → Preferences → Install CLI… (~/bin recommended).")

    if not args.skip_cursor_mcp:
        write_cursor_mcp_sample(sample_mcp, dry_run=args.dry_run)

    print()
    print("Next steps:")
    print(f"  cd {forge_home}")
    print("  hermes")
    print(f"  /skill:{SKILL_NAME}")
    print()
    print("Verification:")
    if not print_checks(verify_checks()):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

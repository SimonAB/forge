#!/usr/bin/env python3
"""Forge GTD dashboard — unified project + task overview for terminal / Herdr panes."""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from forge_dashboard.data import load_snapshot, resolve_forge_home, snapshot_to_dict  # noqa: E402
from forge_dashboard.render import LAYOUTS, render  # noqa: E402


def cmd_refresh(forge_home: Path) -> None:
    """Run the morning-review pull bundle before rendering."""
    script = forge_home / "scripts" / "morning-review-pull.sh"
    if not script.is_file():
        script = SCRIPT_DIR / "morning-review-pull.sh"
    subprocess.run(["bash", str(script)], check=False, cwd=forge_home)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Forge GTD dashboard (projects + task index + calendar).",
    )
    parser.add_argument(
        "--forge-home",
        default=str(resolve_forge_home()),
        help="Forge home directory",
    )
    parser.add_argument(
        "--layout",
        choices=sorted(LAYOUTS),
        default="compact",
        help="Terminal layout (default: compact)",
    )
    parser.add_argument("--show", type=int, default=8, help="Rows per section")
    parser.add_argument("--stale-days", type=float, default=7.0)
    parser.add_argument("--stuck-days", type=float, default=14.0)
    parser.add_argument("--due-days", type=int, default=14)
    parser.add_argument(
        "--refresh",
        action="store_true",
        help="Run morning-review-pull.sh before rendering",
    )
    parser.add_argument(
        "--watch",
        type=float,
        metavar="SECONDS",
        help="Clear and re-render every N seconds (Ctrl+C to stop)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Dump raw snapshot counters as JSON (debug)",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    forge_home = Path(args.forge_home).expanduser()

    def once() -> str:
        if args.refresh:
            cmd_refresh(forge_home)
        snap = load_snapshot(
            forge_home=forge_home,
            stale_days=args.stale_days,
            stuck_days=args.stuck_days,
            due_days=args.due_days,
        )
        if args.json:
            import json

            payload = snapshot_to_dict(snap, show=max(1, args.show))
            return json.dumps(payload, indent=2) + "\n"
        return render(args.layout, snap, show=max(1, args.show))

    if not args.watch:
        output = once()
        sys.stdout.write(output)
        if not args.json and not output.endswith("\n"):
            sys.stdout.write("\n")
        return 0

    interval = max(5.0, float(args.watch))
    try:
        while True:
            sys.stdout.write("\033[2J\033[H")
            sys.stdout.write(once())
            if not args.json:
                sys.stdout.write("\n")
            sys.stdout.flush()
            time.sleep(interval)
    except KeyboardInterrupt:
        sys.stdout.write("\n")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())

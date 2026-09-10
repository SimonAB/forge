#!/usr/bin/env python3
"""Forge mail-open helper — loopback HTTP trampoline for Super Productivity.

Super Productivity blocks ``message://`` in notes. This serves
``http://127.0.0.1:18765/mail/<digest>`` pages that navigate to the stored
Mail URI. Capture / inbox rewrite start it automatically when needed.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from forge_tasks_world.mail_open_http import (  # noqa: E402
    MAIL_OPEN_PORT,
    serve_forever,
)


def _default_forge_home() -> Path:
    """Resolve Forge home from CWD or the usual location."""
    cwd = Path.cwd()
    if (cwd / "config.yaml").is_file():
        return cwd
    candidate = Path.home() / "Documents" / "Software" / "Forge"
    if (candidate / "config.yaml").is_file():
        return candidate
    return cwd


def main() -> int:
    """Parse args and serve until interrupted."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--forge-home",
        type=Path,
        default=None,
        help="Forge home (default: auto-detect)",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=MAIL_OPEN_PORT,
        help=f"Loopback port (default {MAIL_OPEN_PORT})",
    )
    args = parser.parse_args()
    forge_home = (args.forge_home or _default_forge_home()).expanduser().resolve()
    print(
        f"forge-mail-open-httpd listening on http://127.0.0.1:{args.port} "
        f"(forge-home={forge_home})",
        flush=True,
    )
    try:
        serve_forever(forge_home, port=args.port)
    except KeyboardInterrupt:
        print("stopped", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

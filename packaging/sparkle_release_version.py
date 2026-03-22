#!/usr/bin/env python3
"""Print the Sparkle semver from Package.resolved for CI release tooling.

Falls back to 2.9.0 if the pin is missing or the file cannot be read.
"""

from __future__ import annotations

import json
import pathlib
import sys

_DEFAULT = "2.9.0"


def main() -> None:
    path = pathlib.Path(__file__).resolve().parent.parent / "Package.resolved"
    try:
        with path.open(encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, json.JSONDecodeError):
        print(_DEFAULT)
        return

    pins: list = []
    if isinstance(data, dict):
        if "pins" in data and isinstance(data["pins"], list):
            pins = data["pins"]
        elif "object" in data and isinstance(data["object"], dict):
            inner = data["object"].get("pins")
            if isinstance(inner, list):
                pins = inner

    for pin in pins:
        ident = str(pin.get("identity") or pin.get("package") or "").lower()
        if ident != "sparkle":
            continue
        state = pin.get("state")
        if isinstance(state, dict):
            ver = state.get("version")
            if isinstance(ver, str) and ver:
                print(ver)
                return

    print(_DEFAULT)


if __name__ == "__main__":
    main()
    sys.exit(0)

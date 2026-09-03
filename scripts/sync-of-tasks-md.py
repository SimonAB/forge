#!/usr/bin/env python3
"""Deprecated entry point — use scripts/sync-of-tasks-from-of.py."""

from __future__ import annotations

import runpy
from pathlib import Path

if __name__ == "__main__":
    target = Path(__file__).with_name("sync-of-tasks-from-of.py")
    runpy.run_path(str(target), run_name="__main__")

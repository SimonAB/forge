#!/usr/bin/env python3
"""Deprecated path — use scripts/forge-sp-menu-tree.py."""

from __future__ import annotations

import runpy
import sys
from pathlib import Path

print(
    "note: scripts/sp-plugins/apply_finder_menu_tree.py moved to "
    "scripts/forge-sp-menu-tree.py (or: forge superproductivity mirror-menu-tree)",
    file=sys.stderr,
)
target = Path(__file__).resolve().parents[1] / "forge-sp-menu-tree.py"
sys.argv[0] = str(target)
runpy.run_path(str(target), run_name="__main__")

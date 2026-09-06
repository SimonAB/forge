#!/usr/bin/env python3
"""Unit tests for Super Productivity board column mirror helpers."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import MagicMock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from forge_tasks_world.superproductivity import (  # noqa: E402
    mirror_board_column_tags,
    nexus_sp_column_mirror_enabled,
)


class NexusSpColumnMirrorTests(unittest.TestCase):
    """Parse ``nexus.sp_column_mirror`` from config YAML."""

    def test_true(self) -> None:
        text = "nexus:\n  sp_column_mirror: true\n"
        self.assertTrue(nexus_sp_column_mirror_enabled(text))

    def test_false(self) -> None:
        text = "nexus:\n  sp_column_mirror: false\n"
        self.assertFalse(nexus_sp_column_mirror_enabled(text))


class MirrorBoardColumnTagsTests(unittest.TestCase):
    """Board-wide mirror skips unmapped / untagged projects and updates mapped ones."""

    def test_mirrors_mapped_projects_only(self) -> None:
        client = MagicMock()
        client.tags.return_value = [
            {"id": "t-coding", "title": "Coding 🤖"},
            {"id": "t-watch", "title": "Watch 👁️"},
        ]
        client.tasks.side_effect = lambda project_id: [
            {"id": f"task-{project_id}", "tagIds": ["t-watch"]},
        ]
        client.update_task.return_value = {}

        board = [
            {"name": "Forge", "column": "Coding"},
            {"name": "Unmapped", "column": "Watch"},
            {"name": "NoCol", "column": "(none)"},
        ]
        result = mirror_board_column_tags(
            client,
            board_projects=board,
            project_ids={"Forge": "sp-forge", "NoCol": "sp-nocol"},
            column_tags={"Coding": "Coding 🤖", "Watch": "Watch 👁️"},
        )
        self.assertTrue(result["ok"])
        self.assertEqual(result["mirrored"], 1)
        self.assertEqual(result["updated_tasks"], 1)
        reasons = {row["project"]: row["reason"] for row in result["skipped"]}
        self.assertEqual(reasons["Unmapped"], "unmapped")
        self.assertEqual(reasons["NoCol"], "no_column")
        client.update_task.assert_called_once()
        args: tuple[Any, ...] = client.update_task.call_args[0]
        self.assertEqual(args[0], "task-sp-forge")
        self.assertIn("t-coding", args[1]["tagIds"])
        self.assertNotIn("t-watch", args[1]["tagIds"])


if __name__ == "__main__":
    unittest.main()

"""Tests for forge-dashboard layouts."""

from __future__ import annotations

import tempfile
import unittest
from unittest.mock import Mock, patch
from datetime import datetime, timezone
from pathlib import Path

from forge_dashboard.data import (
    CalendarRow,
    DashboardSnapshot,
    DueTaskView,
    ProjectRow,
    load_snapshot,
)
from forge_tasks_world.superproductivity import SpDueItem, SpInboxItem
from forge_dashboard.render import render


class DashboardRenderTests(unittest.TestCase):
    def test_snapshot_uses_sp_without_legacy_database(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "config.yaml").write_text('superproductivity:\n  enabled: true\n  project_ids: {Demo: project1}\n')
            store = Mock()
            store.list_inbox.return_value = [SpInboxItem("capture1", "Reply", "cli", None, None, [])]
            store.due_tasks.return_value = ([SpDueItem(
                "task1", "Write", "Remote title", "project1", datetime.now().date().isoformat(), "next")],
                {"projects": 1, "open_tasks": 2})
            with patch('forge_dashboard.data.resolve_forge_bin', return_value='forge'), \
                 patch('forge_dashboard.data.subprocess.check_output', return_value='{"projects":[{"name":"Demo","path":"/demo","column":"Write"}]}'), \
                 patch('forge_dashboard.data.subprocess.run', return_value=Mock(returncode=0, stdout='{}')), \
                 patch('forge_tasks_world.superproductivity.SpTaskStore', return_value=store):
                snap = load_snapshot(forge_home=root)
            self.assertIsNone(snap.world_error)
            self.assertEqual(snap.world_inbox, 1)
            self.assertEqual(snap.due_today[0].column, "Write")
            self.assertEqual(snap.due_today[0].project_name, "Demo")
            self.assertFalse((root / '.forge/tasks.db').exists())

    def _sample_snapshot(self) -> DashboardSnapshot:
        now = datetime(2026, 9, 2, 8, 0, tzinfo=timezone.utc)
        return DashboardSnapshot(
            generated_at=now,
            projects=[
                ProjectRow(
                    name="Demo",
                    path="/tmp/demo",
                    column="Watch",
                    meta_tags=("URGENT ⚠️",),
                    assignees=(),
                    days_since_activity=3.0,
                )
            ],
            column_counts={"Watch": 1},
            urgent=[
                ProjectRow(
                    name="Demo",
                    path="/tmp/demo",
                    column="Watch",
                    meta_tags=("URGENT ⚠️",),
                    assignees=(),
                    days_since_activity=3.0,
                )
            ],
            calendar_today=[
                CalendarRow(
                    title="Stand-up",
                    calendar="Work",
                    start=now,
                    end=now,
                    all_day=False,
                )
            ],
            due_overdue=[
                DueTaskView(
                    task_id="t1",
                    title="Overdue task",
                    project_name="Demo",
                    project_path="/tmp/demo",
                    section="next",
                    due="2026-09-01",
                    column="Watch",
                )
            ],
            world_open_tasks=5,
        )

    def test_tick_layout(self) -> None:
        text = render("tick", self._sample_snapshot())
        self.assertIn("URG:1", text)
        self.assertIn("overdue:1", text)
        self.assertIn("inbox:0", text)

    def test_compact_layout(self) -> None:
        text = render("compact", self._sample_snapshot(), show=3)
        self.assertIn("Schedule today", text)
        self.assertIn("Watch", text)
        self.assertIn("Overdue task", text)
        self.assertIn("Inbox", text)


if __name__ == "__main__":
    unittest.main()

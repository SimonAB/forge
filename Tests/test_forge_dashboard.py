"""Tests for forge-dashboard layouts."""

from __future__ import annotations

import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from forge_dashboard.data import (
    CalendarRow,
    DashboardSnapshot,
    DueTaskView,
    ProjectRow,
)
from forge_dashboard.render import render


class DashboardRenderTests(unittest.TestCase):
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

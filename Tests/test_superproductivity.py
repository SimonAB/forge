"""Tests for the offline-safe Super Productivity adapter."""

from __future__ import annotations

import tempfile
import unittest
from datetime import date
from unittest.mock import Mock
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parents[1] / "scripts"))

from forge_tasks_world.superproductivity import (  # noqa: E402
    DEFAULT_ENDPOINT,
    SuperProductivityConfig,
    SpTaskStore,
    INBOX_PROJECT_ID,
    combine_notes,
    config_from_yaml_text,
    defer_blocks_export,
    load_ledger,
    merge_snapshots,
    save_ledger,
    split_notes,
    sync_snapshot,
    task_from_remote,
)
from forge_tasks_world.toml_io import TaskRecord  # noqa: E402


class SuperProductivityTests(unittest.TestCase):
    def test_yaml_comments_and_quoted_colons(self):
        config = config_from_yaml_text('''
superproductivity:
  enabled: false # intentionally disabled
  project_ids:
    "Study: phase 2": "abc" # project ID
''')
        self.assertFalse(config.enabled)
        self.assertEqual(config.project_ids, {"Study: phase 2": "abc"})

    def test_yaml_rejects_non_boolean_enabled(self):
        with self.assertRaises(ValueError):
            config_from_yaml_text('superproductivity: {enabled: "false"}')

    def test_due_tasks_include_inbox_even_when_projects_omit_it(self):
        client = Mock()
        client.config.endpoint = DEFAULT_ENDPOINT
        client.projects.return_value = [{"id": "project", "title": "Demo"}]
        today = date.today().isoformat()
        client.tasks.side_effect = lambda project_id, **kwargs: (
            [{"id": "due-inbox", "title": "Reply", "dueDay": today},
             {"id": "done", "title": "Finished", "dueDay": today, "isDone": True}]
            if project_id == INBOX_PROJECT_ID else []
        )
        rows, status = SpTaskStore(Path("/unused"), client).due_tasks(horizon_days=7)
        self.assertEqual([row.task_id for row in rows], ["due-inbox"])
        self.assertEqual(rows[0].project_name, "Inbox")
        self.assertEqual(status["open_tasks"], 1)

    def test_config_rejects_non_loopback(self):
        with self.assertRaises(ValueError):
            SuperProductivityConfig.from_mapping({"endpoint": "https://example.test"})

    def test_config_defaults_to_loopback(self):
        self.assertEqual(SuperProductivityConfig.from_mapping({}).endpoint, DEFAULT_ENDPOINT)

    def test_config_parses_nested_project_ids(self):
        text = """
superproductivity:
  enabled: true
  endpoint: http://127.0.0.1:3876
  project_ids:
    Forge: "abc"
    CausalDynamics.jl: "def"
"""
        config = config_from_yaml_text(text)
        self.assertTrue(config.enabled)
        self.assertEqual(config.project_ids["Forge"], "abc")
        self.assertEqual(config.project_ids["CausalDynamics.jl"], "def")

    def test_config_parses_quoted_project_ids(self):
        text = """
superproductivity:
  enabled: true
  project_ids:
    "Forge": "abc"
    "CausalDynamics.jl": "def"
"""
        config = config_from_yaml_text(text)
        self.assertEqual(config.project_ids["Forge"], "abc")
        self.assertEqual(config.project_ids["CausalDynamics.jl"], "def")

    def test_remote_task_preserves_dates_and_external_identity(self):
        task = task_from_remote(
            {
                "id": "abc",
                "title": "Write",
                "plannedAt": 1_788_678_000_000,
                "dueDay": "2026-09-10",
                "timeEstimate": 30 * 60_000,
                "timeSpent": 5 * 60_000,
                "notes": "Body\n\n<!-- forge:id:local1 -->",
            }
        )
        self.assertEqual(task.id, "local1")
        self.assertEqual(task.external_id, "abc")
        self.assertEqual(task.due, "2026-09-10")
        self.assertEqual(task.estimate_minutes, 30)
        self.assertEqual(task.recorded_minutes, 5)
        self.assertEqual(task.notes, "Body")

    def test_notes_marker_round_trip(self):
        notes = combine_notes("Hello", "task1")
        user, forge_id = split_notes(notes)
        self.assertEqual(user, "Hello")
        self.assertEqual(forge_id, "task1")

    def test_merge_snapshots_three_way(self):
        baseline = {"title": "A", "section_open": True, "due": None, "planned": None,
                    "estimate_minutes": None, "recorded_minutes": None, "notes": None}
        local = dict(baseline, title="Local")
        remote = dict(baseline, title="Remote")
        merged, push, pull, conflicts = merge_snapshots(local, remote, baseline)
        self.assertEqual(conflicts, ["title"])
        self.assertEqual(merged["title"], "Local")
        self.assertEqual(push, [])
        self.assertEqual(pull, [])

        remote_only = dict(baseline, title="Remote")
        merged, push, pull, conflicts = merge_snapshots(baseline, remote_only, baseline)
        self.assertEqual(pull, ["title"])
        self.assertEqual(merged["title"], "Remote")
        self.assertEqual(conflicts, [])

        local_only = dict(baseline, title="Local")
        merged, push, pull, conflicts = merge_snapshots(local_only, baseline, baseline)
        self.assertEqual(push, ["title"])
        self.assertEqual(merged["title"], "Local")

    def test_defer_blocks_export(self):
        task = TaskRecord(id="t1", title="Later", section="next", defer="2099-01-01")
        self.assertTrue(defer_blocks_export(task))
        task2 = TaskRecord(id="t2", title="Now", section="next", defer="2000-01-01")
        self.assertFalse(defer_blocks_export(task2))

    def test_ledger_round_trip(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            ledger = load_ledger(home)
            ledger["tasks"]["sp:abc"] = {"fingerprint": "x"}
            save_ledger(home, ledger)
            self.assertEqual(load_ledger(home)["tasks"]["sp:abc"]["fingerprint"], "x")

    def test_sync_snapshot_ignores_marker(self):
        task = TaskRecord(
            id="t1",
            title="X",
            section="next",
            notes=combine_notes("Body", "t1"),
            external_id="abc",
            external_backend="super-productivity",
        )
        self.assertEqual(sync_snapshot(task)["notes"], "Body")


if __name__ == "__main__":
    unittest.main()

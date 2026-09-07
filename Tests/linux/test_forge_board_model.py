from __future__ import annotations

import subprocess
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from forge_board_model import ForgeBoardClient, snapshot_from_json  # noqa: E402


class BoardModelTests(unittest.TestCase):
    def test_snapshot_preserves_columns_and_joins_sp_counters(self) -> None:
        snapshot = snapshot_from_json(
            {"board": {"columns": [{"name": "Plan", "tag": "Plan 📐"}]},
             "projects": [{"name": "Demo", "path": "/tmp/Demo", "column": "Plan", "metaTags": ["URGENT ⚠️"]}]},
            {"world": {"projects": 3, "open_tasks": 8, "inbox": 2}, "calendar_error": "calendar unavailable on this platform"},
        )
        self.assertEqual(snapshot.by_column["Plan"][0].name, "Demo")
        self.assertTrue(snapshot.by_column["Plan"][0].urgent)
        self.assertEqual(snapshot.sp_open_tasks, 8)
        self.assertEqual(snapshot.calendar_error, "calendar unavailable on this platform")

    def test_client_uses_read_only_json_commands(self) -> None:
        calls: list[list[str]] = []

        def runner(command, **kwargs):
            calls.append(command)
            payload = '{"board":{"columns":[],"projects":[]},"projects":[]}' if command[1] == "board" else '{"world":{}}'
            return subprocess.CompletedProcess(command, 0, payload, "")

        ForgeBoardClient(Path("/tmp/forge"), "/tmp/forge", runner).refresh()
        self.assertEqual(calls, [["/tmp/forge", "board", "--json"], ["/tmp/forge", "dashboard", "--json"]])
        self.assertTrue(all("move" not in call for call in calls))


if __name__ == "__main__":
    unittest.main()

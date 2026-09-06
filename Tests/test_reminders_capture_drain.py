"""Exercise the drain's completion gate without contacting Reminders or SP."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/reminders-capture-drain.sh"


class RemindersCaptureDrainTests(unittest.TestCase):
    def run_drain(self, capture_output):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            osascript = root / "osascript"
            osascript.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
script = sys.stdin.read()
if "rem.completed = true" in script:
    pathlib.Path(os.environ["COMPLETION_LOG"]).touch()
    print(json.dumps({"ok": True}))
else:
    print(json.dumps({"reminders": [{"id": "reminder-1", "title": "Reply"}]}))
''')
            forge = root / "forge"
            forge.write_text('''#!/usr/bin/env python3
import os
print(os.environ["CAPTURE_OUTPUT"])
''')
            osascript.chmod(0o755)
            forge.chmod(0o755)
            completion_log = root / "completed"
            env = dict(os.environ, PATH=f"{root}{os.pathsep}{os.environ['PATH']}",
                       COMPLETION_LOG=str(completion_log), CAPTURE_OUTPUT=capture_output)
            result = subprocess.run(
                ["bash", str(SCRIPT), "--forge", str(forge), "--forge-home", str(root)],
                env=env, capture_output=True, text=True, timeout=15,
            )
            return result.returncode, json.loads(result.stdout), completion_log.exists()

    def test_unconfirmed_capture_never_completes_reminder(self):
        for payload in ("not JSON", "null", "[]", '{}',
                        '{"id":"task-1","backend":"tasks.db"}',
                        '{"id":"","backend":"super-productivity"}'):
            with self.subTest(payload=payload):
                code, summary, completed = self.run_drain(payload)
                self.assertEqual(code, 1)
                self.assertFalse(summary["ok"])
                self.assertEqual(len(summary["failed"]), 1)
                self.assertFalse(completed)

    def test_confirmed_sp_capture_completes_reminder(self):
        code, summary, completed = self.run_drain(
            '{"id":"task-1","backend":"super-productivity"}')
        self.assertEqual(code, 0)
        self.assertTrue(summary["ok"])
        self.assertEqual(summary["completed"][0]["sp_id"], "task-1")
        self.assertTrue(completed)

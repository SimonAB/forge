"""Exercise the drain's completion gate without contacting Reminders or SP."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/reminders-capture-drain.sh"


class RemindersCaptureDrainTests(unittest.TestCase):
    def run_drain(self, capture_output, *, retry=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            osascript = root / "osascript"
            osascript.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
script = sys.stdin.read()
if "rem.completed = true" in script:
    attempt = pathlib.Path(os.environ["COMPLETION_LOG"] + ".attempt")
    if os.environ["RETRY"] == "1" and not attempt.exists():
        attempt.touch()
        sys.exit(1)
    pathlib.Path(os.environ["COMPLETION_LOG"]).touch()
    print(json.dumps({"ok": True}))
else:
    print(json.dumps({"reminders": [{"id": "reminder-1", "title": "Reply"}]}))
''')
            forge = root / "forge"
            forge.write_text('''#!/usr/bin/env python3
import os, pathlib
log = pathlib.Path(os.environ["CAPTURE_LOG"])
log.write_text(log.read_text() + "capture\\n" if log.exists() else "capture\\n")
print(os.environ["CAPTURE_OUTPUT"])
''')
            osascript.chmod(0o755)
            forge.chmod(0o755)
            completion_log = root / "completed"
            env = dict(os.environ, PATH=f"{root}{os.pathsep}{os.environ['PATH']}",
                       COMPLETION_LOG=str(completion_log), CAPTURE_OUTPUT=capture_output,
                       RETRY="1" if retry else "0", CAPTURE_LOG=str(root / "captures"))
            result = subprocess.run(
                ["bash", str(SCRIPT), "--forge", str(forge), "--forge-home", str(root)],
                env=env, capture_output=True, text=True, timeout=15,
            )
            if retry:
                self.assertEqual(result.returncode, 1)
                result = subprocess.run(
                    ["bash", str(SCRIPT), "--forge", str(forge), "--forge-home", str(root)],
                    env=env, capture_output=True, text=True, timeout=15,
                )
                self.assertEqual((root / "captures").read_text().splitlines(), ["capture"])
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

    def test_retry_completes_without_duplicate_capture(self):
        code, summary, completed = self.run_drain(
            '{"id":"task-1","backend":"super-productivity"}', retry=True)
        self.assertEqual(code, 0)
        self.assertTrue(completed)

    def test_uncertain_capture_is_not_retried(self):
        code, summary, completed = self.run_drain('not JSON', retry=True)
        self.assertEqual(code, 1)
        self.assertIn('previous capture unconfirmed', summary['failed'][0]['error'])
        self.assertFalse(completed)

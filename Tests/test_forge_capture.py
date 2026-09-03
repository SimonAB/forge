"""Tests for Forge inbox capture."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from forge_tasks_world.capture import (
    CaptureStore,
    infer_link_kind,
    message_uri,
    sniff_clipboard_link,
    task_db_path,
)


class CaptureTests(unittest.TestCase):
    def test_infer_and_sniff(self) -> None:
        self.assertEqual(infer_link_kind("message://abc"), "mail")
        self.assertEqual(infer_link_kind("https://example.com"), "url")
        self.assertEqual(
            sniff_clipboard_link("message://%3cabc%3e"),
            ("mail", "message://%3cabc%3e"),
        )
        self.assertIsNone(sniff_clipboard_link("not a link with spaces"))
        self.assertEqual(message_uri("abc@example.com"), "message://%3cabc@example.com%3e")

    def test_capture_assign_complete(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            forge_home = Path(tmp)
            store = CaptureStore(forge_home)
            item = store.capture(
                "Reply to student",
                link="message://demo",
                kind="mail",
                source="assistant",
            )
            self.assertEqual(item.section, "inbox")
            self.assertEqual(item.links[0]["kind"], "mail")

            inbox = store.list_inbox()
            self.assertEqual(len(inbox), 1)
            self.assertEqual(inbox[0].title, "Reply to student")

            project_dir = forge_home / "projects" / "Demo"
            project_dir.mkdir(parents=True)
            store.assign(item.task_id, project_dir, "Demo", section="next")
            self.assertEqual(store.list_inbox(), [])

            row = store.db.get_task(item.task_id)
            assert row is not None
            self.assertEqual(row["section"], "next")
            self.assertEqual(row["project_path"], str(project_dir))

            store.complete(item.task_id)
            row = store.db.get_task(item.task_id)
            assert row is not None
            self.assertEqual(row["section"], "done")
            store.close()

            self.assertTrue(task_db_path(forge_home).is_file())

    def test_link_only_file_unless_stash(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            forge_home = Path(tmp)
            source = forge_home / "notes.txt"
            source.write_text("hello", encoding="utf-8")
            store = CaptureStore(forge_home)
            linked = store.capture("Read notes", file_path=source, stash=False)
            self.assertTrue(linked.links[0]["uri"].startswith("file:"))
            self.assertFalse((forge_home / ".forge" / "inbox").exists())

            stashed = store.capture("Archive notes", file_path=source, stash=True)
            stash_uri = stashed.links[0]["uri"]
            self.assertIn("/.forge/inbox/", stash_uri)
            store.close()


if __name__ == "__main__":
    unittest.main()

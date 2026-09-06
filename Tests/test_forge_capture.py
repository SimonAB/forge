"""Tests for Forge inbox capture."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from forge_tasks_world.capture import (
    CaptureStore,
    extract_uri_from_notes,
    format_sp_note_attachment,
    format_sp_note_link,
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
        self.assertEqual(
            message_uri("weird id with space"),
            "message://%3cweird%20id%20with%20space%3e",
        )

    def test_sp_note_link_wrap_and_extract(self) -> None:
        http = "https://example.com/path(1)"
        http_line = format_sp_note_link(http, kind="url")
        self.assertEqual(http_line, "[example.com](https://example.com/path(1%29)")
        self.assertEqual(
            extract_uri_from_notes(http_line),
            "https://example.com/path(1)",
        )
        self.assertEqual(
            extract_uri_from_notes("<message://%3cid%3e>"),
            "message://%3cid%3e",
        )
        self.assertEqual(
            extract_uri_from_notes("message://%3cold%3e"),
            "message://%3cold%3e",
        )

    def test_sp_mail_uses_inetloc_trampoline(self) -> None:
        mail = message_uri("id@example.com")
        with tempfile.TemporaryDirectory() as tmp:
            forge_home = Path(tmp)
            lines = format_sp_note_attachment(mail, kind="mail", forge_home=forge_home)
            self.assertEqual(len(lines), 2)
            self.assertTrue(lines[0].startswith("[Open in Mail](file://"))
            self.assertTrue(lines[0].endswith(".inetloc)"))
            self.assertEqual(lines[1], f"[forge:uri:{mail}]")
            notes = "\n".join(lines)
            self.assertEqual(extract_uri_from_notes(notes), mail)
            locs = list((forge_home / ".forge" / "mail-open").glob("*.inetloc"))
            self.assertEqual(len(locs), 1)
            self.assertIn(mail, locs[0].read_text(encoding="utf-8"))
            self.assertEqual(extract_uri_from_notes(lines[0]), mail)
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

            tasks_path = project_dir / "TASKS.toml"
            self.assertTrue(tasks_path.is_file())
            text = tasks_path.read_text(encoding="utf-8")
            self.assertIn("Reply to student", text)
            self.assertIn("[[next]]", text)
            self.assertIn(item.task_id, text)

            store.complete(item.task_id)
            row = store.db.get_task(item.task_id)
            assert row is not None
            self.assertEqual(row["section"], "done")
            done_text = tasks_path.read_text(encoding="utf-8")
            self.assertIn("[[done]]", done_text)
            self.assertNotIn("[[next]]", done_text)
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

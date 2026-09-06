"""Tests for context-aware capture resolution."""

from __future__ import annotations

import unittest
from pathlib import Path

from forge_tasks_world.context_capture import resolve_captures


class ContextCaptureTests(unittest.TestCase):
    """Resolver priority and note attachment."""

    def test_files_win_and_take_selection_note(self) -> None:
        rows = resolve_captures(
            files=[Path("/tmp/demo.pdf")],
            text="highlighted snippet",
            prefer="auto",
            frontmost="com.apple.mail",
            platform_name="Darwin",
            mail_fetcher=lambda: [{"title": "Should not run", "uri": "message://x"}],
        )
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0].strategy, "file")
        self.assertEqual(rows[0].note, "highlighted snippet")
        self.assertTrue(rows[0].title.startswith("File:"))

    def test_mail_frontmost_uses_selection_and_note(self) -> None:
        rows = resolve_captures(
            text="please reply",
            prefer="auto",
            frontmost="com.apple.mail",
            platform_name="Darwin",
            mail_fetcher=lambda: [
                {"title": "Hello", "uri": "message://%3cid%3e"},
            ],
        )
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0].strategy, "mail")
        self.assertEqual(rows[0].title, "Hello")
        self.assertEqual(rows[0].link, "message://%3cid%3e")
        self.assertEqual(rows[0].note, "please reply")

    def test_browser_frontmost_uses_tab_url(self) -> None:
        rows = resolve_captures(
            text="quote from page",
            prefer="auto",
            frontmost="com.apple.Safari",
            platform_name="Darwin",
            browser_fetcher=lambda kind: "https://example.com/path/page",
        )
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0].strategy, "browser")
        self.assertEqual(rows[0].kind, "url")
        self.assertEqual(rows[0].link, "https://example.com/path/page")
        self.assertEqual(rows[0].note, "quote from page")

    def test_linux_skips_mail_auto(self) -> None:
        rows = resolve_captures(
            text="todo later",
            prefer="auto",
            frontmost="com.apple.mail",
            platform_name="Linux",
            mail_fetcher=lambda: [{"title": "Nope", "uri": "message://x"}],
        )
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0].strategy, "text")
        self.assertEqual(rows[0].title, "todo later")

    def test_plain_uri_selection(self) -> None:
        rows = resolve_captures(
            text="https://example.org/a",
            prefer="auto",
            platform_name="Linux",
        )
        self.assertEqual(rows[0].strategy, "uri")
        self.assertEqual(rows[0].kind, "url")
        self.assertEqual(rows[0].link, "https://example.org/a")


if __name__ == "__main__":
    unittest.main()

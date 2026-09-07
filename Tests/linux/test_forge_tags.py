#!/usr/bin/env python3
"""Tests for Finder-compatible tag xattrs on Linux."""

from __future__ import annotations

import os
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parents[2] / "scripts" / "linux"
FORGE_SCRIPT = SCRIPT_DIR / "forge"
sys.path.insert(0, str(SCRIPT_DIR))

import forge_tags  # noqa: E402
import forge_sidecar  # noqa: E402


class FinderTagCompatTests(unittest.TestCase):
    """Round-trip tags using the same binary plist Forge writes on macOS."""

    def test_binary_plist_matches_array_of_strings(self) -> None:
        """Encoded payload must be a binary plist array of strings."""

        data = forge_tags.encode_tags(["Plan 📐", "🔥 Forge"])
        self.assertTrue(data.startswith(b"bplist"))
        self.assertEqual(plistlib.loads(data), ["Plan 📐", "🔥 Forge"])

    def test_linux_write_uses_user_namespace(self) -> None:
        """Linux writes must use the user. xattr prefix."""

        self.assertEqual(
            forge_tags.write_xattr_name(),
            "user.com.apple.metadata:_kMDItemUserTags",
        )

    def test_round_trip_xattr_and_sidecar(self) -> None:
        """Writing tags persists both xattr and sidecar; reads agree."""

        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / "VHP2"
            folder.mkdir()
            tags = ["Coding 🤖", "🔥 Forge", "URGENT ⚠️"]
            forge_tags.write_tags(folder, tags)
            self.assertEqual(forge_tags.read_tags(folder), tags)
            self.assertEqual(forge_tags.read_sidecar(folder), tags)
            raw = os.getxattr(folder, forge_tags.LINUX_TAG_XATTR)
            self.assertEqual(plistlib.loads(raw), tags)
            self.assertEqual(
                os.getxattr(folder, forge_tags.XDG_TAG_XATTR).decode("utf-8"),
                ",".join(tags),
            )

    def test_replace_workflow_preserves_meta(self) -> None:
        """Column moves keep meta and project tags."""

        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / "proj"
            folder.mkdir()
            forge_tags.write_tags(folder, ["Plan 📐", "🔥 Forge", "#Alice"])
            forge_tags.replace_workflow_tag(
                folder,
                "Write ✒️",
                workflow_tags={"Plan 📐", "Write ✒️", "Coding 🤖"},
            )
            got = forge_tags.read_tags(folder)
            self.assertIn("Write ✒️", got)
            self.assertNotIn("Plan 📐", got)
            self.assertIn("🔥 Forge", got)
            self.assertIn("#Alice", got)

    def test_import_apple_named_xattr_when_present(self) -> None:
        """Reader accepts the bare Apple key if the filesystem allows it."""

        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / "from-mac"
            folder.mkdir()
            payload = forge_tags.encode_tags(["Watch 👁️"])
            try:
                os.setxattr(folder, forge_tags.APPLE_TAG_XATTR, payload)
            except OSError:
                self.skipTest("filesystem rejects bare Apple xattr name")
            self.assertEqual(forge_tags.read_tags(folder), ["Watch 👁️"])

    def test_kanban_sidecar_round_trip(self) -> None:
        """Portable TOML sidecar preserves workflow, metadata, and assignees."""

        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / "Demo"
            folder.mkdir()
            original = forge_sidecar.KanbanSidecar(
                column="Coding",
                workflow_tag="Coding 🤖",
                meta=("URGENT ⚠️",),
                assignees=("#Alice",),
                updated_at="2026-09-07T12:00:00.000Z",
                source="forge-move",
            )
            forge_sidecar.save(folder, original)
            self.assertEqual(forge_sidecar.load(folder), original)

    def test_fs_migrate_creates_canonical_sidecar(self) -> None:
        """The CLI migrates existing local tags only when --apply is supplied."""

        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            projects = home / "projects"
            folder = projects / "Demo"
            folder.mkdir(parents=True)
            forge_tags.write_tags(folder, ["Coding 🤖", "🔥 Forge", "#Alice"])
            (home / "config.yaml").write_text(
                "project_roots: [projects]\n"
                "board:\n"
                "  columns: [{name: Coding, tag: 'Coding 🤖', colour: 5}]\n"
                "  meta_tags: []\n"
                "project_tag: '🔥 Forge'\n",
                encoding="utf-8",
            )
            env = dict(os.environ, FORGE_HOME=str(home))
            preview = subprocess.run(
                [sys.executable, str(FORGE_SCRIPT), "fs", "migrate", "--json"],
                text=True, capture_output=True, check=True, env=env,
            )
            self.assertIn("create-sidecar", preview.stdout)
            self.assertIsNone(forge_sidecar.load(folder))
            subprocess.run(
                [sys.executable, str(FORGE_SCRIPT), "fs", "migrate", "--apply"],
                text=True, capture_output=True, check=True, env=env,
            )
            self.assertEqual(forge_sidecar.load(folder).column, "Coding")


if __name__ == "__main__":
    unittest.main()

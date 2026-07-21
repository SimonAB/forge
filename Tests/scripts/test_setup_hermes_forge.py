"""Tests for scripts/setup-hermes-forge.py (Hermes config merge logic)."""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / "scripts" / "setup-hermes-forge.py"


def load_setup_module():
    """Import setup-hermes-forge as a module."""

    spec = importlib.util.spec_from_file_location("setup_hermes_forge", SCRIPT_PATH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules["setup_hermes_forge"] = module
    spec.loader.exec_module(module)
    return module


setup = load_setup_module()


class TestHermesConfigMerge(unittest.TestCase):
    """Hermes YAML external_dirs merge helpers."""

    def test_read_empty_external_dirs(self) -> None:
        text = "skills:\n  external_dirs: []\n"
        self.assertEqual(setup.read_external_dirs(text), [])

    def test_read_list_external_dirs(self) -> None:
        text = """
skills:
  external_dirs:
    - /tmp/a
    - /tmp/b
"""
        self.assertEqual(setup.read_external_dirs(text), ["/tmp/a", "/tmp/b"])

    def test_merge_appends_when_missing(self) -> None:
        text = "skills:\n  external_dirs: []\n"
        merged, changed = setup.merge_external_dir(text, "/tmp/forge/.hermes/skills")
        self.assertTrue(changed)
        self.assertIn("/tmp/forge/.hermes/skills", merged)

    def test_merge_idempotent(self) -> None:
        text = """
skills:
  external_dirs:
    - /tmp/forge/.hermes/skills
"""
        merged, changed = setup.merge_external_dir(text, "/tmp/forge/.hermes/skills")
        self.assertFalse(changed)
        self.assertEqual(merged, text)


if __name__ == "__main__":
    unittest.main()

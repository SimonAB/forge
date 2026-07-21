from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / "scripts" / "forge-brief--with-full.py"


def load_setup_module():
    """Import forge-brief--with-full.py as a Python module."""
    spec = importlib.util.spec_from_file_location("forge_brief_with_full", SCRIPT_PATH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules["forge_brief_with_full"] = module
    spec.loader.exec_module(module)
    return module


brief = load_setup_module()


class TestBriefMatching(unittest.TestCase):
    def test_match_allows_specific_single_token(self) -> None:
        # "Causal" overlaps once with the project name; "causal" is not a common token.
        projects = {"causal-dynamics-concept-notes"}
        events = [{"title": "Causal Model Hulda"}]

        matches = brief.match_cal(events, projects)
        self.assertIn("Causal Model Hulda", matches["causal-dynamics-concept-notes"])

    def test_match_suppresses_generic_tokens(self) -> None:
        # "meeting" is in the suppression list; a single generic overlap should not match.
        projects = {"some-project-meeting"}
        events = [{"title": "Weekly meeting"}]

        matches = brief.match_cal(events, projects)
        self.assertNotIn("Weekly meeting", matches["some-project-meeting"])

    def test_match_allows_multiple_overlaps(self) -> None:
        # Multiple token overlap should match even if one token is generic.
        projects = {"causal-concept-notes"}
        events = [{"title": "Causal Notes meeting"}]

        matches = brief.match_cal(events, projects)
        self.assertIn("Causal Notes meeting", matches["causal-concept-notes"])


if __name__ == "__main__":
    unittest.main()


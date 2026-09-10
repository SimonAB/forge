"""Unit tests for OmniFocus → Super Productivity destination policy."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[1] / "scripts"))

from forge_tasks_world.of_sp_destinations import (  # noqa: E402
    build_sp_destination_map,
    destination_for_task,
)


class OfSpDestinationTests(unittest.TestCase):
    def test_one_to_one_uses_finder_name(self) -> None:
        of_data = {
            "projects": [{"id": "p1", "name": "PhD – Sophie Mwinyi", "forgeFolder": None}],
            "tasks": [
                {
                    "id": "t1",
                    "name": "Draft chapter",
                    "ofProjectName": "PhD – Sophie Mwinyi",
                    "completed": False,
                }
            ],
        }
        forge_paths = {"Sophie Mwinyi - PhD": Path("/tmp/Sophie Mwinyi - PhD")}
        dest = build_sp_destination_map(of_data, forge_paths=forge_paths)
        self.assertEqual(dest["PhD – Sophie Mwinyi"], "Sophie Mwinyi - PhD")

    def test_collision_uses_finder_name(self) -> None:
        of_data = {
            "projects": [
                {"id": "p1", "name": "PGT – Fundamentals of Programming"},
                {"id": "p2", "name": "PGT – Intro to R"},
            ],
            "tasks": [
                {
                    "id": "t1",
                    "name": "FoP week 1",
                    "ofProjectName": "PGT – Fundamentals of Programming",
                    "completed": False,
                },
                {
                    "id": "t2",
                    "name": "R lab",
                    "ofProjectName": "PGT – Intro to R",
                    "completed": False,
                },
            ],
        }
        forge_paths = {
            "PGT": Path("/tmp/PGT"),
            "2. Fundamentals of Programming": Path("/tmp/2. Fundamentals of Programming"),
        }
        dest = build_sp_destination_map(of_data, forge_paths=forge_paths)
        self.assertEqual(
            dest["PGT – Fundamentals of Programming"],
            "2. Fundamentals of Programming",
        )
        self.assertEqual(dest["PGT – Intro to R"], "PGT")

    def test_task_forge_folder_beats_of_project_map(self) -> None:
        dest_by_of = {"Viral Host Predictor v2": "Viruses-ViralHostPredictor"}
        forge_paths = {"Viruses-ViralHostPredictor": Path("/tmp/Viruses-ViralHostPredictor")}
        sp_by_title = {
            "Viruses-ViralHostPredictor": "id1",
            "VHP2_manuscript": "id2",
        }
        task = {
            "ofProjectName": "Viral Host Predictor v2",
            "forgeFolder": "VHP2_manuscript",
        }
        self.assertEqual(
            destination_for_task(
                task,
                dest_by_of_project=dest_by_of,
                forge_paths=forge_paths,
                sp_by_title=sp_by_title,
            ),
            "VHP2_manuscript",
        )

    def test_no_board_folder_uses_of_title(self) -> None:
        of_data = {
            "projects": [{"id": "p1", "name": "Single Actions @Home"}],
            "tasks": [
                {
                    "id": "t1",
                    "name": "Pay lunches",
                    "ofProjectName": "Single Actions @Home",
                    "completed": False,
                }
            ],
        }
        dest = build_sp_destination_map(of_data, forge_paths={})
        self.assertEqual(dest["Single Actions @Home"], "Single Actions @Home")

    def test_fallback_to_of_title_when_finder_sp_missing(self) -> None:
        dest_by_of = {"PGT – Intro to R": "PGT"}
        task = {"ofProjectName": "PGT – Intro to R", "forgeFolder": None}
        sp_by_title = {"PGT – Intro to R": "id-intro"}
        self.assertEqual(
            destination_for_task(
                task,
                dest_by_of_project=dest_by_of,
                forge_paths={"PGT": Path("/tmp/PGT")},
                sp_by_title=sp_by_title,
            ),
            "PGT – Intro to R",
        )


if __name__ == "__main__":
    unittest.main()

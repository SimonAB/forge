"""Tests for Forge project tasks (TASKS.toml + task index)."""

from __future__ import annotations

import tempfile
import unittest
from datetime import date
from pathlib import Path

from forge_tasks_world.md_convert import convert_tasks_md_to_project_tasks
from forge_tasks_world.toml_io import (
    ProjectTasks,
    TaskRecord,
    load_project_tasks,
    write_project_tasks,
)
from forge_tasks_world.world_db import WorldDatabase


class ProjectTasksTests(unittest.TestCase):
    def test_markdown_link_and_tags(self) -> None:
        md = Path(tempfile.mkdtemp()) / "TASKS.md"
        md.write_text(
            "\n".join(
                [
                    "# Demo",
                    "",
                    "## Next Actions",
                    "",
                    "- [ ] [Reply to student](message://abc) @due(2026-09-07) @ctx(email) <!-- id:abc123 -->",
                ]
            ),
            encoding="utf-8",
        )
        project_tasks = convert_tasks_md_to_project_tasks(md)
        self.assertEqual(len(project_tasks.tasks), 1)
        task = project_tasks.tasks[0]
        self.assertEqual(task.title, "Reply to student")
        self.assertEqual(task.links.get("mail"), "message://abc")
        self.assertEqual(task.due, "2026-09-07")
        self.assertEqual(task.ctx, ["email"])

    def test_toml_round_trip_and_ingest(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            project_dir = root / "Demo Project"
            project_dir.mkdir()
            tasks_path = project_dir / "TASKS.toml"

            project_tasks = ProjectTasks(
                project="Demo Project",
                tasks=[
                    TaskRecord(
                        id="t1",
                        title="Write spike",
                        section="next",
                        due="2026-09-10",
                        ctx=["writing"],
                    )
                ],
            )
            write_project_tasks(project_tasks, tasks_path)
            loaded = load_project_tasks(tasks_path)
            self.assertEqual(loaded.tasks[0].title, "Write spike")

            db_path = root / "world.db"
            db = WorldDatabase(db_path)
            db.ingest_project(
                project_path=project_dir,
                project_name="Demo Project",
                column_name="Watch",
                project_tasks=loaded,
                tasks_path=tasks_path,
            )
            due = db.due_tasks(horizon_days=30)
            db.close()
            self.assertEqual(len(due), 1)
            self.assertEqual(due[0].task_id, "t1")

    def test_readable_writer_layout(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            project_dir = root / "Demo Project"
            project_dir.mkdir()
            tasks_path = project_dir / "TASKS.toml"

            project_tasks = ProjectTasks(
                project="Demo Project",
                tasks=[
                    TaskRecord(
                        id="t1",
                        title="Write spike",
                        section="next",
                        due="2026-09-10",
                        ctx=["writing"],
                        notes="First paragraph.\nSecond line.",
                    )
                ],
                notes_body="Project-level notes.",
            )
            write_project_tasks(project_tasks, tasks_path)
            text = tasks_path.read_text(encoding="utf-8")
            self.assertIn('title = "Write spike"', text)
            self.assertIn("due = 2026-09-10", text)
            self.assertIn("# Forge-assigned; do not edit", text)
            self.assertLess(text.index("title"), text.index('id = "t1"'))

            loaded = load_project_tasks(tasks_path)
            self.assertEqual(loaded.tasks[0].due, "2026-09-10")
            self.assertEqual(loaded.tasks[0].notes, "First paragraph.\nSecond line.")
            self.assertEqual(loaded.notes_body, "Project-level notes.")

    def test_pretty_show(self) -> None:
        from forge_tasks_world.show import render_project_tasks

        project_tasks = ProjectTasks(
            project="Demo",
            tasks=[
                TaskRecord(
                    id="w1",
                    title="Await lab reply",
                    section="waiting",
                    due="2026-09-05",
                    ctx=["email"],
                ),
                TaskRecord(
                    id="n1",
                    title="Draft methods",
                    section="next",
                ),
            ],
        )
        rendered = render_project_tasks(project_tasks, column="Watch", today=date(2026, 9, 2))
        self.assertIn("Demo  (Watch)", rendered)
        self.assertIn("☐ Await lab reply", rendered)
        self.assertIn("[waiting]", rendered)
        self.assertIn("@email", rendered)
        self.assertIn("☐ Draft methods", rendered)

    def test_checked_moves_to_done_on_apply(self) -> None:
        from forge_tasks_world.toml_io import apply_checked_completions

        project_tasks = ProjectTasks(
            project="Demo",
            tasks=[
                TaskRecord(
                    id="c1",
                    title="Finish spike",
                    section="next",
                    checked=True,
                ),
                TaskRecord(
                    id="c2",
                    title="Still open",
                    section="next",
                ),
            ],
        )
        changed = apply_checked_completions(project_tasks, today=date(2026, 9, 3))
        self.assertTrue(changed)
        by_id = {task.id: task for task in project_tasks.tasks}
        self.assertEqual(by_id["c1"].section, "done")
        self.assertEqual(by_id["c1"].done, "2026-09-03")
        self.assertFalse(by_id["c1"].checked)
        self.assertEqual(by_id["c2"].section, "next")

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "TASKS.toml"
            write_project_tasks(project_tasks, path)
            text = path.read_text(encoding="utf-8")
            self.assertIn("[[done]]", text)
            self.assertIn("done = 2026-09-03", text)
            field_lines = [
                line.strip()
                for line in text.splitlines()
                if line.strip() and not line.strip().startswith("#")
            ]
            self.assertFalse(any(line.startswith("checked") for line in field_lines))


if __name__ == "__main__":
    unittest.main()

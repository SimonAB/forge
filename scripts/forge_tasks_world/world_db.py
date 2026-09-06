"""SQLite task database (`.forge/tasks.db`) for inbox + cross-project queries."""

from __future__ import annotations

import hashlib
import json
import sqlite3
from dataclasses import dataclass
from datetime import date, datetime, timezone
from pathlib import Path

from .toml_io import ProjectTasks, TaskRecord

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS projects (
    path TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    column_name TEXT,
    tasks_path TEXT,
    tasks_mtime REAL,
    tasks_fingerprint TEXT,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tasks (
    id TEXT PRIMARY KEY,
    project_path TEXT REFERENCES projects(path) ON DELETE SET NULL,
    section TEXT NOT NULL,
    title TEXT NOT NULL,
    due TEXT,
    defer TEXT,
    planned TEXT,
    done TEXT,
    contexts TEXT,
    assignees TEXT,
    flagged INTEGER NOT NULL DEFAULT 0,
    links TEXT,
    notes TEXT,
    external_id TEXT,
    external_backend TEXT,
    estimate_minutes INTEGER,
    recorded_minutes INTEGER,
    fingerprint TEXT NOT NULL,
    source TEXT,
    created_at TEXT,
    updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_tasks_project ON tasks(project_path);
CREATE INDEX IF NOT EXISTS idx_tasks_section ON tasks(section);
CREATE INDEX IF NOT EXISTS idx_tasks_due ON tasks(due);
CREATE INDEX IF NOT EXISTS idx_tasks_inbox ON tasks(section) WHERE section = 'inbox';

CREATE VIRTUAL TABLE IF NOT EXISTS tasks_fts USING fts5(
    task_id UNINDEXED,
    project_name,
    title,
    notes,
    content='',
    tokenize='porter unicode61'
);
"""


@dataclass
class DueTask:
    task_id: str
    title: str
    project_name: str
    project_path: str
    section: str
    due: str
    contexts: list[str]
    assignees: list[str]


class WorldDatabase:
    """Materialised task database: inbox captures + project task index."""

    def __init__(self, db_path: Path) -> None:
        self.db_path = db_path
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(self.db_path)
        self.conn.row_factory = sqlite3.Row
        self.conn.execute("PRAGMA foreign_keys = ON")
        self.conn.executescript(SCHEMA_SQL)
        self._migrate_schema()
        self.conn.execute(
            "INSERT OR REPLACE INTO meta(key, value) VALUES ('schema', '3')"
        )
        self.conn.commit()

    def close(self) -> None:
        self.conn.close()

    def _migrate_schema(self) -> None:
        """Rename legacy columns and allow nullable project_path for inbox."""
        rows = self.conn.execute("PRAGMA table_info(projects)").fetchall()
        columns = {row[1] for row in rows}
        for old_name, new_name in (
            ("leaf_path", "tasks_path"),
            ("leaf_mtime", "tasks_mtime"),
            ("leaf_fingerprint", "tasks_fingerprint"),
        ):
            if old_name in columns and new_name not in columns:
                self.conn.execute(
                    f"ALTER TABLE projects RENAME COLUMN {old_name} TO {new_name}"
                )

        task_info = self.conn.execute("PRAGMA table_info(tasks)").fetchall()
        task_cols = {row[1]: row for row in task_info}
        if "source" not in task_cols:
            self.conn.execute("ALTER TABLE tasks ADD COLUMN source TEXT")
        if "created_at" not in task_cols:
            self.conn.execute("ALTER TABLE tasks ADD COLUMN created_at TEXT")
        for name, sql_type in (("planned", "TEXT"), ("external_id", "TEXT"),
                               ("external_backend", "TEXT"), ("estimate_minutes", "INTEGER"),
                               ("recorded_minutes", "INTEGER")):
            if name not in task_cols:
                self.conn.execute(f"ALTER TABLE tasks ADD COLUMN {name} {sql_type}")

        # Recreate tasks table when project_path is still NOT NULL (pre-inbox schema).
        project_col = task_cols.get("project_path")
        if project_col is not None and project_col[3] == 1:
            self.conn.executescript(
                """
                CREATE TABLE tasks_new (
                    id TEXT PRIMARY KEY,
                    project_path TEXT REFERENCES projects(path) ON DELETE SET NULL,
                    section TEXT NOT NULL,
                    title TEXT NOT NULL,
                    due TEXT,
                    defer TEXT,
                    planned TEXT,
                    done TEXT,
                    contexts TEXT,
                    assignees TEXT,
                    flagged INTEGER NOT NULL DEFAULT 0,
                    links TEXT,
                    notes TEXT,
                    external_id TEXT,
                    external_backend TEXT,
                    estimate_minutes INTEGER,
                    recorded_minutes INTEGER,
                    fingerprint TEXT NOT NULL,
                    source TEXT,
                    created_at TEXT,
                    updated_at TEXT NOT NULL
                );
                INSERT INTO tasks_new(
                    id, project_path, section, title, due, defer, planned, done,
                    contexts, assignees, flagged, links, notes, external_id, external_backend,
                    estimate_minutes, recorded_minutes, fingerprint,
                    source, created_at, updated_at
                )
                SELECT
                    id, project_path, section, title, due, defer, NULL, done,
                    contexts, assignees, flagged, links, notes, NULL, NULL, NULL, NULL, fingerprint,
                    source, created_at, updated_at
                FROM tasks;
                DROP TABLE tasks;
                ALTER TABLE tasks_new RENAME TO tasks;
                CREATE INDEX IF NOT EXISTS idx_tasks_project ON tasks(project_path);
                CREATE INDEX IF NOT EXISTS idx_tasks_section ON tasks(section);
                CREATE INDEX IF NOT EXISTS idx_tasks_due ON tasks(due);
                CREATE INDEX IF NOT EXISTS idx_tasks_inbox ON tasks(section)
                    WHERE section = 'inbox';
                """
            )
        self.conn.commit()

    def capture_inbox(
        self,
        *,
        task_id: str,
        title: str,
        source: str,
        notes: str | None,
        links: list[dict[str, str]],
    ) -> dict[str, str]:
        """Insert a new inbox task (no project)."""
        now = _utc_now()
        fingerprint = f"inbox|{title}|{notes or ''}|{json.dumps(links, sort_keys=True)}"
        self.conn.execute(
            """
            INSERT INTO tasks(
                id, project_path, section, title, due, defer, done,
                contexts, assignees, flagged, links, notes, fingerprint,
                source, created_at, updated_at
            ) VALUES (?, NULL, 'inbox', ?, NULL, NULL, NULL, '[]', '[]', 0, ?, ?, ?, ?, ?, ?)
            """,
            (
                task_id,
                title,
                json.dumps(links),
                notes,
                fingerprint,
                source,
                now,
                now,
            ),
        )
        self.conn.execute("DELETE FROM tasks_fts WHERE task_id = ?", (task_id,))
        self.conn.execute(
            """
            INSERT INTO tasks_fts(task_id, project_name, title, notes)
            VALUES (?, ?, ?, ?)
            """,
            (task_id, "Inbox", title, notes or ""),
        )
        self.conn.commit()
        return {
            "id": task_id,
            "title": title,
            "section": "inbox",
            "source": source,
            "created_at": now,
        }

    def list_inbox(self) -> list[sqlite3.Row]:
        """Return open inbox tasks oldest-first."""
        return list(
            self.conn.execute(
                """
                SELECT id, title, source, created_at, notes, links, updated_at
                FROM tasks
                WHERE section = 'inbox'
                ORDER BY COALESCE(created_at, updated_at) ASC, title ASC
                """
            )
        )

    def get_task(self, task_id: str) -> sqlite3.Row | None:
        """Return one task row or None."""
        return self.conn.execute(
            "SELECT * FROM tasks WHERE id = ?", (task_id,)
        ).fetchone()

    def assign_task(
        self,
        *,
        task_id: str,
        project_path: Path,
        project_name: str,
        section: str,
        column_name: str | None,
    ) -> None:
        """Attach an inbox (or other) task to a project."""
        now = _utc_now()
        self.conn.execute(
            """
            INSERT INTO projects(path, name, column_name, tasks_path, tasks_mtime, tasks_fingerprint, updated_at)
            VALUES (?, ?, ?, NULL, NULL, NULL, ?)
            ON CONFLICT(path) DO UPDATE SET
                name = excluded.name,
                column_name = COALESCE(excluded.column_name, projects.column_name),
                updated_at = excluded.updated_at
            """,
            (str(project_path), project_name, column_name, now),
        )
        row = self.get_task(task_id)
        if row is None:
            raise KeyError(f"unknown task id: {task_id}")
        self.conn.execute(
            """
            UPDATE tasks
            SET project_path = ?, section = ?, updated_at = ?
            WHERE id = ?
            """,
            (str(project_path), section, now, task_id),
        )
        self.conn.execute("DELETE FROM tasks_fts WHERE task_id = ?", (task_id,))
        self.conn.execute(
            """
            INSERT INTO tasks_fts(task_id, project_name, title, notes)
            VALUES (?, ?, ?, ?)
            """,
            (task_id, project_name, row["title"], row["notes"] or ""),
        )
        self.conn.commit()

    def complete_task(self, task_id: str) -> None:
        """Mark a task completed."""
        now = _utc_now()
        today = date.today().isoformat()
        row = self.get_task(task_id)
        if row is None:
            raise KeyError(f"unknown task id: {task_id}")
        self.conn.execute(
            """
            UPDATE tasks
            SET section = 'done', done = COALESCE(done, ?), updated_at = ?
            WHERE id = ?
            """,
            (today, now, task_id),
        )
        self.conn.commit()

    def inbox_count(self) -> int:
        """Return number of open inbox items."""
        return int(
            self.conn.execute(
                "SELECT COUNT(*) FROM tasks WHERE section = 'inbox'"
            ).fetchone()[0]
        )

    def ingest_project(
        self,
        project_path: Path,
        project_name: str,
        column_name: str | None,
        project_tasks: ProjectTasks,
        tasks_path: Path,
    ) -> tuple[int, int]:
        """Upsert one project's TASKS.toml into the task index."""
        tasks_mtime = tasks_path.stat().st_mtime
        fingerprint = self._project_tasks_fingerprint(project_tasks)
        now = _utc_now()

        self.conn.execute(
            """
            INSERT INTO projects(path, name, column_name, tasks_path, tasks_mtime, tasks_fingerprint, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(path) DO UPDATE SET
                name = excluded.name,
                column_name = excluded.column_name,
                tasks_path = excluded.tasks_path,
                tasks_mtime = excluded.tasks_mtime,
                tasks_fingerprint = excluded.tasks_fingerprint,
                updated_at = excluded.updated_at
            """,
            (
                str(project_path),
                project_name,
                column_name,
                str(tasks_path),
                tasks_mtime,
                fingerprint,
                now,
            ),
        )

        existing_ids = {
            row["id"]
            for row in self.conn.execute(
                """
                SELECT id FROM tasks
                WHERE project_path = ? AND section != 'inbox'
                """,
                (str(project_path),),
            )
        }
        seen_ids: set[str] = set()
        upserted = 0

        for task in project_tasks.tasks:
            seen_ids.add(task.id)
            self._upsert_task(project_path, project_name, task, now)
            upserted += 1

        removed = 0
        for stale_id in existing_ids - seen_ids:
            self.conn.execute("DELETE FROM tasks WHERE id = ?", (stale_id,))
            self.conn.execute(
                "DELETE FROM tasks_fts WHERE task_id = ?", (stale_id,)
            )
            removed += 1

        self.conn.commit()
        return upserted, removed

    def _upsert_task(
        self,
        project_path: Path,
        project_name: str,
        task: TaskRecord,
        updated_at: str,
    ) -> None:
        existing = self.get_task(task.id)
        created_at = existing["created_at"] if existing else updated_at
        source = existing["source"] if existing and existing["source"] else "toml"
        links_payload = (
            [{"kind": key, "uri": value} for key, value in task.links.items()]
            if task.links
            else []
        )
        self.conn.execute(
            """
            INSERT INTO tasks(
                id, project_path, section, title, due, defer, planned, done,
                contexts, assignees, flagged, links, notes, external_id,
                external_backend, estimate_minutes, recorded_minutes, fingerprint,
                source, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                project_path = excluded.project_path,
                section = excluded.section,
                title = excluded.title,
                due = excluded.due,
                defer = excluded.defer,
                planned = excluded.planned,
                done = excluded.done,
                contexts = excluded.contexts,
                assignees = excluded.assignees,
                flagged = excluded.flagged,
                links = excluded.links,
                notes = excluded.notes,
                external_id = excluded.external_id,
                external_backend = excluded.external_backend,
                estimate_minutes = excluded.estimate_minutes,
                recorded_minutes = excluded.recorded_minutes,
                fingerprint = excluded.fingerprint,
                updated_at = excluded.updated_at
            """,
            (
                task.id,
                str(project_path),
                task.section,
                task.title,
                task.due,
                task.defer,
                task.planned,
                task.done,
                json.dumps(task.ctx),
                json.dumps(task.assignees),
                1 if task.flagged else 0,
                json.dumps(links_payload),
                task.notes,
                task.external_id,
                task.external_backend,
                task.estimate_minutes,
                task.recorded_minutes,
                task.fingerprint(),
                source,
                created_at,
                updated_at,
            ),
        )
        self.conn.execute("DELETE FROM tasks_fts WHERE task_id = ?", (task.id,))
        self.conn.execute(
            """
            INSERT INTO tasks_fts(task_id, project_name, title, notes)
            VALUES (?, ?, ?, ?)
            """,
            (task.id, project_name, task.title, task.notes or ""),
        )

    def due_tasks(
        self,
        *,
        horizon_days: int = 7,
        include_overdue: bool = True,
        assignee: str | None = None,
    ) -> list[DueTask]:
        """Return open tasks with due dates within the horizon."""
        today = date.today()
        horizon = today.toordinal() + horizon_days
        rows = self.conn.execute(
            """
            SELECT t.id, t.title, t.section, t.due, t.contexts, t.assignees,
                   COALESCE(p.name, 'Inbox') AS project_name,
                   COALESCE(p.path, '') AS project_path
            FROM tasks t
            LEFT JOIN projects p ON p.path = t.project_path
            WHERE t.section IN ('next', 'waiting')
              AND t.due IS NOT NULL AND trim(t.due) != ''
            ORDER BY t.due ASC, project_name ASC, t.title ASC
            """
        )

        results: list[DueTask] = []
        for row in rows:
            due_text = str(row["due"])
            due_day = _parse_date_prefix(due_text)
            if due_day is None:
                continue
            ordinal = due_day.toordinal()
            if not include_overdue and ordinal < today.toordinal():
                continue
            if ordinal > horizon:
                continue

            contexts = json.loads(row["contexts"] or "[]")
            assignees = json.loads(row["assignees"] or "[]")
            if assignee:
                needle = assignee.lstrip("#").lower()
                hay = [value.lower() for value in assignees]
                if needle not in hay:
                    continue

            results.append(
                DueTask(
                    task_id=row["id"],
                    title=row["title"],
                    project_name=row["project_name"],
                    project_path=row["project_path"],
                    section=row["section"],
                    due=due_text,
                    contexts=contexts,
                    assignees=assignees,
                )
            )
        return results

    def status(self) -> dict[str, int | str]:
        projects = self.conn.execute("SELECT COUNT(*) FROM projects").fetchone()[0]
        tasks = self.conn.execute("SELECT COUNT(*) FROM tasks").fetchone()[0]
        open_tasks = self.conn.execute(
            "SELECT COUNT(*) FROM tasks WHERE section IN ('next', 'waiting', 'someday', 'inbox')"
        ).fetchone()[0]
        inbox = self.inbox_count()
        db_path = str(self.db_path)
        return {
            "projects": projects,
            "tasks": tasks,
            "open_tasks": open_tasks,
            "inbox": inbox,
            "db_path": db_path,
        }

    @staticmethod
    def _project_tasks_fingerprint(project_tasks: ProjectTasks) -> str:
        digest = hashlib.sha256()
        for task in sorted(project_tasks.tasks, key=lambda item: item.id):
            digest.update(task.fingerprint().encode("utf-8"))
            digest.update(b"\n")
        if project_tasks.notes_body:
            digest.update(project_tasks.notes_body.encode("utf-8"))
        return digest.hexdigest()


def _utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def _parse_date_prefix(value: str) -> date | None:
    prefix = value.strip()[:10]
    try:
        return date.fromisoformat(prefix)
    except ValueError:
        return None

"""Load board, calendar, and task-index data for the Forge dashboard."""

from __future__ import annotations

import json
import os
import subprocess
from collections import Counter
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any

from forge_tasks_world.world_db import DueTask, WorldDatabase


def resolve_forge_home() -> Path:
    """Return Forge home from env or common locations."""
    env = os.environ.get("FORGE_DIR", "").strip()
    if env:
        return Path(env).expanduser()
    home = Path.home()
    for candidate in (
        home / "Documents/Software/Forge",
        home / "Documents/Forge",
        home / "Documents/Work/Projects/Forge",
    ):
        if (candidate / "config.yaml").exists() or (candidate / "config.sample.yaml").exists():
            return candidate
    return home / "Documents/Software/Forge"


def resolve_forge_bin(forge_home: Path) -> str:
    """Return an executable forge CLI path."""
    candidates: list[str] = []
    if env := os.environ.get("FORGE_BIN", "").strip():
        candidates.append(env)
    candidates.extend(
        [
            os.path.expanduser("~/bin/forge"),
            "/Applications/Forge.app/Contents/Resources/bin/forge",
            str(forge_home / ".build" / "debug" / "forge"),
        ]
    )
    seen: set[str] = set()
    for path in candidates:
        if not path or path in seen:
            continue
        seen.add(path)
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path
    raise SystemExit(
        "forge CLI not found. Install via Forge → Preferences → Install CLI, "
        "or set FORGE_BIN."
    )


def is_urgent_tag(tag: str) -> bool:
    """Return True if a tag is an URGENT meta tag."""
    return tag.upper().startswith("URGENT")


@dataclass(frozen=True)
class ProjectRow:
    """Kanban project summary for the dashboard."""

    name: str
    path: str
    column: str
    meta_tags: tuple[str, ...]
    assignees: tuple[str, ...]
    days_since_activity: float

    @property
    def is_urgent(self) -> bool:
        return any(is_urgent_tag(tag) for tag in self.meta_tags)


@dataclass(frozen=True)
class CalendarRow:
    """Calendar event for the dashboard."""

    title: str
    calendar: str
    start: datetime
    end: datetime
    all_day: bool


@dataclass(frozen=True)
class DueTaskView:
    """Due task with kanban column for display."""

    task_id: str
    title: str
    project_name: str
    project_path: str
    section: str
    due: str
    column: str | None


@dataclass(frozen=True)
class InboxView:
    """Inbox capture for dashboard display."""

    task_id: str
    title: str
    source: str | None


@dataclass
class DashboardSnapshot:
    """Point-in-time dashboard data."""

    generated_at: datetime
    projects: list[ProjectRow] = field(default_factory=list)
    column_counts: dict[str, int] = field(default_factory=dict)
    urgent: list[ProjectRow] = field(default_factory=list)
    stale: list[ProjectRow] = field(default_factory=list)
    stuck: list[ProjectRow] = field(default_factory=list)
    calendar_today: list[CalendarRow] = field(default_factory=list)
    calendar_error: str | None = None
    due_overdue: list[DueTaskView] = field(default_factory=list)
    due_today: list[DueTaskView] = field(default_factory=list)
    due_upcoming: list[DueTaskView] = field(default_factory=list)
    world_projects: int = 0
    world_open_tasks: int = 0
    world_inbox: int = 0
    world_error: str | None = None
    inbox: list[InboxView] = field(default_factory=list)


def _parse_projects(raw: dict[str, Any]) -> list[ProjectRow]:
    rows: list[ProjectRow] = []
    for item in raw.get("projects", []) or []:
        rows.append(
            ProjectRow(
                name=str(item.get("name") or ""),
                path=str(item.get("path") or ""),
                column=str(item.get("column") or "(none)"),
                meta_tags=tuple(item.get("metaTags") or ()),
                assignees=tuple(item.get("assignees") or ()),
                days_since_activity=float(item.get("daysSinceActivity") or 0.0),
            )
        )
    return rows


def _parse_calendar(raw: dict[str, Any], *, now: datetime) -> list[CalendarRow]:
    events: list[CalendarRow] = []
    today = now.date()

    def parse_iso(value: str) -> datetime | None:
        value = (value or "").strip()
        if not value:
            return None
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone()
        except ValueError:
            return None

    for item in raw.get("events", []) or []:
        start = parse_iso(str(item.get("startDate") or ""))
        end = parse_iso(str(item.get("endDate") or ""))
        if not start or not end or start.date() != today:
            continue
        if not item.get("isAllDay") and end <= now:
            continue
        events.append(
            CalendarRow(
                title=str(item.get("title") or ""),
                calendar=str(item.get("calendarTitle") or ""),
                start=start,
                end=end,
                all_day=bool(item.get("isAllDay")),
            )
        )
    events.sort(key=lambda row: (row.start, row.title.lower()))
    return events


def _parse_due_day(value: str) -> date | None:
    prefix = (value or "").strip()[:10]
    if not prefix:
        return None
    try:
        return date.fromisoformat(prefix)
    except ValueError:
        return None


def _sort_neglect(projects: list[ProjectRow]) -> list[ProjectRow]:
    return sorted(projects, key=lambda row: (-row.days_since_activity, row.name.lower()))


def load_snapshot(
    *,
    forge_home: Path | None = None,
    stale_days: float = 7.0,
    stuck_days: float = 14.0,
    due_days: int = 14,
    calendar_timeout: float = 15.0,
) -> DashboardSnapshot:
    """Gather board, calendar, and task-index data for rendering."""
    root = forge_home or resolve_forge_home()
    forge_bin = resolve_forge_bin(root)
    now = datetime.now().astimezone()
    snap = DashboardSnapshot(generated_at=now)

    board_raw = subprocess.check_output(
        [forge_bin, "board", "--json"], cwd=root, text=True
    )
    snap.projects = _parse_projects(json.loads(board_raw))
    snap.column_counts = dict(Counter(row.column for row in snap.projects))
    snap.urgent = _sort_neglect([row for row in snap.projects if row.is_urgent])
    snap.stale = _sort_neglect(
        [
            row
            for row in snap.projects
            if row.days_since_activity >= stale_days and row.column != "Paused"
        ]
    )
    snap.stuck = _sort_neglect(
        [
            row
            for row in snap.projects
            if row.column in {"Watch", "Coding", "Write", "Review"}
            and row.days_since_activity >= stuck_days
        ]
    )

    try:
        calendar_raw = subprocess.run(
            [forge_bin, "calendar", "--days", "1", "--json"],
            cwd=root,
            text=True,
            capture_output=True,
            timeout=calendar_timeout,
            check=False,
        )
        if calendar_raw.returncode != 0:
            snap.calendar_error = (calendar_raw.stderr or calendar_raw.stdout or "").strip()
        else:
            snap.calendar_today = _parse_calendar(json.loads(calendar_raw.stdout or "{}"), now=now)
    except subprocess.TimeoutExpired:
        snap.calendar_error = f"calendar timed out after {calendar_timeout:g}s"
    except Exception as exc:  # pragma: no cover
        snap.calendar_error = str(exc)

    from forge_tasks_world.capture import task_db_path

    db_path = task_db_path(root)
    if not db_path.is_file():
        snap.world_error = "tasks.db missing — run sync-of-tasks-from-of.py or forge capture"
        return snap

    column_by_path = {row.path: row.column for row in snap.projects}
    today = now.date()

    def wrap(item: DueTask) -> DueTaskView:
        return DueTaskView(
            task_id=item.task_id,
            title=item.title,
            project_name=item.project_name,
            project_path=item.project_path,
            section=item.section,
            due=item.due,
            column=column_by_path.get(item.project_path),
        )

    try:
        db = WorldDatabase(db_path)
        try:
            stats = db.status()
            snap.world_projects = int(stats["projects"])
            snap.world_open_tasks = int(stats["open_tasks"])
            snap.world_inbox = int(stats.get("inbox") or 0)
            for row in db.list_inbox():
                snap.inbox.append(
                    InboxView(
                        task_id=row["id"],
                        title=row["title"],
                        source=row["source"],
                    )
                )
            for item in db.due_tasks(horizon_days=max(0, due_days), include_overdue=True):
                due_day = _parse_due_day(item.due)
                if due_day is None:
                    continue
                if due_day < today:
                    snap.due_overdue.append(wrap(item))
                elif due_day == today:
                    snap.due_today.append(wrap(item))
                else:
                    snap.due_upcoming.append(wrap(item))
        finally:
            db.close()
    except Exception as exc:  # pragma: no cover
        snap.world_error = str(exc)

    for bucket in (snap.due_overdue, snap.due_today, snap.due_upcoming):
        bucket.sort(key=lambda item: (item.due, item.project_name.lower(), item.title.lower()))

    return snap


def snapshot_to_dict(snap: DashboardSnapshot, *, show: int = 8) -> dict:
    """Serialise a dashboard snapshot for JSON export (Forge.app popover, scripts)."""

    def project_row(row: ProjectRow) -> dict:
        return {
            "name": row.name,
            "column": row.column,
            "days_since_activity": round(row.days_since_activity, 1),
            "assignees": list(row.assignees),
        }

    def due_row(item: DueTaskView) -> dict:
        return {
            "task_id": item.task_id,
            "due": item.due,
            "column": item.column,
            "project": item.project_name,
            "title": item.title,
            "waiting": item.section == "waiting",
        }

    def event_row(event: CalendarRow) -> dict:
        if event.all_day:
            time_s = "all-day"
        else:
            time_s = f"{event.start.strftime('%H:%M')}–{event.end.strftime('%H:%M')}"
        return {
            "title": event.title,
            "calendar": event.calendar,
            "time": time_s,
            "all_day": event.all_day,
        }

    limit = max(1, show)
    return {
        "generated_at": snap.generated_at.isoformat(),
        "columns": snap.column_counts,
        "active_count": sum(
            count
            for name, count in snap.column_counts.items()
            if name not in {"Shipped", "Paused", "(none)"}
        ),
        "world": {
            "projects": snap.world_projects,
            "open_tasks": snap.world_open_tasks,
            "inbox": snap.world_inbox,
            "error": snap.world_error,
        },
        "inbox": [
            {
                "task_id": item.task_id,
                "title": item.title,
                "source": item.source,
            }
            for item in snap.inbox[:limit]
        ],
        "inbox_count": snap.world_inbox,
        "calendar_error": snap.calendar_error,
        "calendar_today": [event_row(event) for event in snap.calendar_today[:limit]],
        "due_overdue": [due_row(item) for item in snap.due_overdue[:limit]],
        "due_today": [due_row(item) for item in snap.due_today[:limit]],
        "due_upcoming": [due_row(item) for item in snap.due_upcoming[:limit]],
        "due_counts": {
            "overdue": len(snap.due_overdue),
            "today": len(snap.due_today),
            "upcoming": len(snap.due_upcoming),
        },
        "urgent": [project_row(row) for row in snap.urgent[:limit]],
        "stuck": [project_row(row) for row in snap.stuck[:limit]],
        "stale_count": len(snap.stale),
    }

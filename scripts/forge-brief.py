#!/usr/bin/env python3
"""
Generate a concise Forge kanban brief from `forge board --json`.

Focus:
- Due tasks and inbox from Super Productivity when enabled (else legacy task index)
- URGENT-tagged projects
- neglected (stale) projects by days since activity
- overloaded columns and obvious board hygiene issues (e.g. missing column tag)

This script is read-only: it does not modify project columns or tags.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from collections import Counter
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence

FORGE_DIR = os.environ.get("FORGE_DIR", os.path.expanduser("~/Documents/Software/Forge"))
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)


def _resolve_forge_bin() -> str:
    """Return an executable forge CLI path."""

    candidates: list[str] = []
    if env := os.environ.get("FORGE_BIN", "").strip():
        candidates.append(env)
    candidates.extend(
        [
            os.path.expanduser("~/bin/forge"),
            "/Applications/Forge.app/Contents/Resources/bin/forge",
            os.path.join(FORGE_DIR, ".build", "debug", "forge"),
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
        "or set FORGE_BIN to the forge binary."
    )


def _is_urgent_tag(tag: str) -> bool:
    """Return True if a tag is an URGENT meta tag (prefix match)."""

    return tag.upper().startswith("URGENT")


@dataclass(frozen=True)
class Project:
    """Normalised view of a Forge project entry."""

    name: str
    path: str
    column: str
    workflow_tag: str
    radar_bucket: str
    meta_tags: tuple[str, ...]
    assignees: tuple[str, ...]
    tags: tuple[str, ...]
    activity_source: str
    activity_modification_date: str
    days_since_activity: float

    @property
    def is_urgent(self) -> bool:
        """Return True if the project is marked URGENT."""

        return any(_is_urgent_tag(t) for t in self.meta_tags) or any(
            _is_urgent_tag(t) for t in self.tags
        )


@dataclass(frozen=True)
class DueTaskRow:
    """Open task with a due date from the task index."""

    task_id: str
    title: str
    project_name: str
    project_path: str
    section: str
    due: str
    column: str | None


@dataclass(frozen=True)
class InboxRow:
    """Open inbox capture awaiting processing."""

    task_id: str
    title: str
    source: str | None
    created_at: str | None


def _task_index_path() -> Path:
    """Return the materialised task database path (tasks.db, migrating world.db)."""

    from forge_tasks_world.capture import task_db_path

    return task_db_path(Path(FORGE_DIR).expanduser())


def _load_inbox() -> tuple[list[InboxRow], str | None]:
    """Return inbox items from Super Productivity when enabled, else tasks.db."""
    forge_home = Path(FORGE_DIR).expanduser()
    try:
        from forge_tasks_world.superproductivity import SpTaskStore, config_from_file

        if config_from_file(forge_home / "config.yaml").enabled:
            store = SpTaskStore(forge_home)
            rows = store.list_inbox()
            items = [
                InboxRow(
                    task_id=row.task_id,
                    title=row.title,
                    source=row.source,
                    created_at=row.created_at,
                )
                for row in rows
            ]
            return (items, None)
    except Exception as exc:  # pragma: no cover
        return ([], f"Super Productivity inbox unreadable: {exc}")

    db_path = _task_index_path()
    if not db_path.is_file():
        return ([], None)
    try:
        from forge_tasks_world.world_db import WorldDatabase

        db = WorldDatabase(db_path)
        try:
            rows = db.list_inbox()
        finally:
            db.close()
    except Exception as exc:  # pragma: no cover
        return ([], f"inbox unreadable: {exc}")

    items: list[InboxRow] = []
    for row in rows:
        items.append(
            InboxRow(
                task_id=row["id"],
                title=row["title"],
                source=row["source"],
                created_at=row["created_at"],
            )
        )
    return (items, None)


def _load_due_tasks_from_index(
    *,
    due_days: int,
    projects: Sequence[Project],
) -> tuple[list[DueTaskRow], dict[str, int | str] | None, str | None]:
    """
    Return due tasks from Super Productivity when enabled, else `.forge/tasks.db`.

    Returns (due_rows, status_dict, error_message).
    """

    forge_home = Path(FORGE_DIR).expanduser()
    column_by_name = {p.name: p.column for p in projects}
    column_by_path = {p.path: p.column for p in projects}

    try:
        from forge_tasks_world.superproductivity import SpTaskStore, config_from_file

        if config_from_file(forge_home / "config.yaml").enabled:
            store = SpTaskStore(forge_home)
            raw_due, status = store.due_tasks(horizon_days=max(0, due_days), include_overdue=True)
            rows = [
                DueTaskRow(
                    task_id=item.task_id,
                    title=item.title,
                    project_name=item.project_name,
                    project_path=item.project_name,
                    section=item.section,
                    due=item.due,
                    column=column_by_name.get(item.project_name),
                )
                for item in raw_due
            ]
            return (rows, status, None)
    except Exception as exc:  # pragma: no cover - defensive for brief generation
        return ([], None, f"Super Productivity dues unreadable: {exc}")

    db_path = _task_index_path()
    if not db_path.is_file():
        return ([], None, f"task index not found ({db_path}); enable Super Productivity or run ingest")

    try:
        from forge_tasks_world.world_db import WorldDatabase

        db = WorldDatabase(db_path)
        try:
            status = db.status()
            raw_due = db.due_tasks(horizon_days=max(0, due_days), include_overdue=True)
        finally:
            db.close()
    except Exception as exc:  # pragma: no cover - defensive for brief generation
        return ([], None, f"task index unreadable: {exc}")

    rows: list[DueTaskRow] = []
    for item in raw_due:
        rows.append(
            DueTaskRow(
                task_id=item.task_id,
                title=item.title,
                project_name=item.project_name,
                project_path=item.project_path,
                section=item.section,
                due=item.due,
                column=column_by_path.get(item.project_path),
            )
        )
    return (rows, status, None)


def _parse_due_day(due: str) -> date | None:
    """Parse the calendar day from a due string."""

    prefix = (due or "").strip()[:10]
    if not prefix:
        return None
    try:
        return date.fromisoformat(prefix)
    except ValueError:
        return None


def _format_due_task(row: DueTaskRow) -> str:
    """Format one due task line for the brief."""

    due_day = _parse_due_day(row.due)
    due_s = due_day.isoformat() if due_day else row.due[:16]
    column = row.column or "?"
    waiting = " [waiting]" if row.section == "waiting" else ""
    return f"{due_s}\t{column}\t{row.project_name}\t{row.title}{waiting}"


@dataclass(frozen=True)
class CalendarEvent:
    """A Calendar.app event (local time)."""

    title: str
    calendar: str
    start: datetime
    end: datetime
    all_day: bool


def _run_forge_board_json() -> Mapping[str, Any]:
    """Return parsed JSON from `forge board --json`."""

    try:
        output = subprocess.check_output(
            [_resolve_forge_bin(), "board", "--json"], text=True
        )
    except FileNotFoundError:
        raise SystemExit(
            "forge CLI not found. Install via Forge → Preferences → Install CLI, "
            "or set FORGE_BIN to the forge binary."
        )
    except subprocess.CalledProcessError as exc:
        raise SystemExit(exc.output.strip() or "forge board --json failed.")
    return json.loads(output)


def _parse_projects(data: Mapping[str, Any]) -> list[Project]:
    """Convert raw board JSON into Project records."""

    projects: list[Project] = []
    for p in data.get("projects", []) or []:
        projects.append(
            Project(
                name=str(p.get("name") or ""),
                path=str(p.get("path") or ""),
                column=str(p.get("column") or "(none)"),
                workflow_tag=str(p.get("workflowTag") or ""),
                radar_bucket=str(p.get("radarBucket") or ""),
                meta_tags=tuple(p.get("metaTags") or ()),
                assignees=tuple(p.get("assignees") or ()),
                tags=tuple(p.get("tags") or ()),
                activity_source=str(p.get("activitySource") or ""),
                activity_modification_date=str(p.get("activityModificationDate") or ""),
                days_since_activity=float(p.get("daysSinceActivity") or 0.0),
            )
        )
    return projects


def _format_age(days: float) -> str:
    """Format an age value (in days) as a compact string."""

    if days >= 365:
        return f"{days/365:.1f}y"
    if days >= 30:
        return f"{days/30:.1f}mo"
    if days >= 7:
        return f"{days:.0f}d"
    return f"{days:.1f}d"


def _now_utc_iso() -> str:
    """Return a UTC timestamp string for display."""

    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _local_now() -> datetime:
    """Return the current local datetime."""

    return datetime.now().astimezone()


def _try_run_calendar_events(
    *,
    days: int,
    timeout_seconds: float,
    calendar_names: Sequence[str] | None,
) -> tuple[list[CalendarEvent], str | None]:
    """
    Return (events, error_message).

    Uses Calendar.app via AppleScript. If permissions are denied or Calendar is unavailable,
    this returns ([], <reason>).
    """

    if days <= 0:
        return ([], None)

    wanted_names = [n.strip() for n in (calendar_names or []) if n.strip()]
    wanted_literal = "{" + ", ".join(f"\"{n.replace('\"', '')}\"" for n in wanted_names) + "}"

    # Use Forge's own EventKit-backed reader (fast, robust) via `forge calendar --json`.
    # This avoids the slow AppleScript approach and matches what Forge.app/CLI already uses.
    try:
        completed = subprocess.run(
            [_resolve_forge_bin(), "calendar", "--days", str(int(days)), "--json"],
            text=True,
            capture_output=True,
            timeout=timeout_seconds,
            check=False,
        )
    except FileNotFoundError:
        return ([], "forge CLI not found (required for Calendar integration).")
    except subprocess.TimeoutExpired:
        return ([], f"forge calendar timed out after {timeout_seconds:g}s.")

    if completed.returncode != 0:
        msg = (completed.stderr or completed.stdout or "").strip()
        return ([], msg or "forge calendar failed.")

    try:
        payload = json.loads(completed.stdout or "{}")
    except json.JSONDecodeError:
        return ([], "forge calendar returned invalid JSON.")

    raw_events = payload.get("events", []) or []

    def parse_iso(s: str) -> datetime | None:
        s = (s or "").strip()
        if not s:
            return None
        # forge emits e.g. 2026-04-23T22:59:59Z
        try:
            return datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone()
        except ValueError:
            return None

    wanted = {n.strip() for n in (calendar_names or []) if n.strip()}

    events: list[CalendarEvent] = []
    for ev in raw_events:
        cal_title = str(ev.get("calendarTitle") or "")
        if wanted and cal_title not in wanted:
            continue
        title = str(ev.get("title") or "")
        start = parse_iso(str(ev.get("startDate") or ""))
        end = parse_iso(str(ev.get("endDate") or ""))
        if not start or not end:
            continue
        all_day = bool(ev.get("isAllDay"))
        events.append(CalendarEvent(title=title, calendar=cal_title, start=start, end=end, all_day=all_day))

    events.sort(key=lambda e: (e.start, e.end, e.title.casefold()))
    return (events, None)


def _format_event_time(ev: CalendarEvent) -> str:
    """Format an event time range compactly."""

    if ev.all_day:
        return "All-day"
    start_s = ev.start.strftime("%H:%M")
    end_s = ev.end.strftime("%H:%M")
    return f"{start_s}–{end_s}"


def _is_today(dt: datetime, *, now: datetime) -> bool:
    """Return True if dt is on the same local date as now."""

    return dt.astimezone().date() == now.astimezone().date()


def _is_past_event(ev: CalendarEvent, *, now: datetime) -> bool:
    """Return True if an event has fully ended before now (local time)."""

    if ev.all_day:
        return False
    return ev.end <= now


def _column_priority(column: str) -> int:
    """Sort columns from 'work in progress' to 'done/paused'."""

    return {
        "Watch": 1,
        "Coding": 2,
        "Write": 3,
        "Review": 4,
        "Plan": 5,
        "Paused": 6,
        "Shipped": 7,
        "(none)": 8,
    }.get(column, 99)


def _sorted_by_neglect(projects: Sequence[Project]) -> list[Project]:
    """Return projects sorted by neglect (most stale first)."""

    return sorted(
        projects,
        key=lambda p: (-p.days_since_activity, _column_priority(p.column), p.name.casefold()),
    )


def _print_kv(title: str, lines: Iterable[str]) -> None:
    """Print a titled section with indented lines."""

    print(f"\n{title}")
    for line in lines:
        print(f"- {line}")


def build_brief(
    *,
    projects: Sequence[Project],
    stale_days: float,
    show: int,
    urgent_show: int,
    overdue_active_days: float,
    calendar_days: int,
    calendar_warn_hours: float,
    calendar_timeout_seconds: float,
    calendar_names: Sequence[str] | None,
    due_days: int,
    include_task_index: bool,
) -> str:
    """Build and return the full brief as a string."""

    urgent = [p for p in projects if p.is_urgent]
    urgent_sorted = sorted(urgent, key=lambda p: (-p.days_since_activity, p.name.casefold()))

    paused = [p for p in projects if p.column == "Paused"]
    paused_sorted = _sorted_by_neglect(paused)

    stale = [p for p in projects if p.days_since_activity >= stale_days and p.column != "Paused"]
    stale_sorted = _sorted_by_neglect(stale)

    active_overdue = [
        p for p in projects if p.column in {"Watch", "Coding", "Write", "Review"} and p.days_since_activity >= overdue_active_days
    ]
    active_overdue_sorted = _sorted_by_neglect(active_overdue)

    missing_column = [p for p in projects if p.column == "(none)" or not p.workflow_tag]
    missing_column_sorted = sorted(missing_column, key=lambda p: (p.column, p.name.casefold()))

    counts = Counter(p.column for p in projects)
    counts_lines = [f"{col}: {counts[col]}" for col in sorted(counts, key=lambda c: (_column_priority(c), c))]

    out: list[str] = []
    out.append(f"Forge brief ({_now_utc_iso()})")

    now_local = _local_now()
    if calendar_days > 0:
        events, cal_err = _try_run_calendar_events(
            days=calendar_days,
            timeout_seconds=calendar_timeout_seconds,
            calendar_names=calendar_names,
        )
        out.append(f"\nCalendar (next {calendar_days} days)")
        if cal_err:
            out.append(f"- Unavailable: {cal_err}")
            if "timed out" in cal_err and not calendar_names:
                out.append("- Hint: restrict calendars via --calendar-calendars \"Work,Home\"")
        elif not events:
            out.append("- No events found")
        else:
            todays = [e for e in events if _is_today(e.start, now=now_local) and not _is_past_event(e, now=now_local)]
            upcoming = [e for e in events if not _is_today(e.start, now=now_local)]
            warn_cutoff = now_local + timedelta(hours=calendar_warn_hours)
            warns = [
                e
                for e in events
                if e.start >= now_local and e.start <= warn_cutoff and not _is_today(e.start, now=now_local)
            ]

            out.append("- Today")
            if todays:
                for ev in todays[:25]:
                    out.append(f"  - {_format_event_time(ev)}\t{ev.title}")
            else:
                out.append("  - None")

            out.append("- Upcoming")
            if upcoming:
                for ev in upcoming[:25]:
                    day = ev.start.strftime("%a")
                    date_s = ev.start.strftime("%d %b")
                    out.append(f"  - {day} {date_s}\t{_format_event_time(ev)}\t{ev.title}")
            else:
                out.append("  - None")

            out.append(f"- Warnings (within {calendar_warn_hours:g}h)")
            if warns:
                for ev in warns[:25]:
                    in_hours = (ev.start - now_local).total_seconds() / 3600.0
                    day = ev.start.strftime("%a")
                    out.append(f"  - in {in_hours:.1f}h\t{day}\t{_format_event_time(ev)}\t{ev.title}")
            else:
                out.append("  - None")

    if include_task_index:
        inbox_rows, inbox_err = _load_inbox()
        out.append(f"\nInbox ({len(inbox_rows)})")
        if inbox_err:
            out.append(f"- Unavailable: {inbox_err}")
        elif inbox_rows:
            for row in inbox_rows[:show]:
                source = f" [{row.source}]" if row.source else ""
                out.append(f"  - {row.title}{source}")
            if len(inbox_rows) > show:
                out.append(f"  - … and {len(inbox_rows) - show} more")
        else:
            out.append("  - None")

        due_rows, index_status, index_err = _load_due_tasks_from_index(
            due_days=due_days, projects=projects
        )
        today = _local_now().date()
        overdue = [row for row in due_rows if (day := _parse_due_day(row.due)) and day < today]
        due_today = [row for row in due_rows if (day := _parse_due_day(row.due)) and day == today]
        upcoming = [row for row in due_rows if (day := _parse_due_day(row.due)) and day > today]

        out.append(f"\nDue tasks (horizon {due_days} days)")
        if index_err:
            out.append(f"- Unavailable: {index_err}")
        else:
            if index_status:
                out.append(
                    f"- Backend: {index_status.get('backend', 'tasks.db')}; "
                    f"{index_status['projects']} project(s), "
                    f"{index_status['open_tasks']} open task(s) "
                    f"({index_status['db_path']})"
                )
            out.append(f"- Overdue ({len(overdue)})")
            if overdue:
                for row in overdue[:show]:
                    out.append(f"  - {_format_due_task(row)}")
                if len(overdue) > show:
                    out.append(f"  - … and {len(overdue) - show} more")
            else:
                out.append("  - None")
            out.append(f"- Due today ({len(due_today)})")
            if due_today:
                for row in due_today[:show]:
                    out.append(f"  - {_format_due_task(row)}")
            else:
                out.append("  - None")
            out.append(f"- Upcoming ({len(upcoming)})")
            if upcoming:
                for row in upcoming[:show]:
                    out.append(f"  - {_format_due_task(row)}")
                if len(upcoming) > show:
                    out.append(f"  - … and {len(upcoming) - show} more")
            else:
                out.append("  - None")

    out.append("\nColumn load")
    out.extend([f"- {line}" for line in counts_lines])

    out.append(f"\nURGENT ({len(urgent_sorted)})")
    if urgent_sorted:
        for p in urgent_sorted[:urgent_show]:
            assignee = f" ({', '.join('#' + a for a in p.assignees)})" if p.assignees else ""
            out.append(f"- {_format_age(p.days_since_activity)}\t{p.column}\t{p.name}{assignee}")
        if len(urgent_sorted) > urgent_show:
            out.append(f"- … and {len(urgent_sorted) - urgent_show} more")
    else:
        out.append("- None")

    out.append(f"\nNeglected (≥ {stale_days:g} days) ({len(stale_sorted)})")
    if stale_sorted:
        for p in stale_sorted[:show]:
            out.append(f"- {_format_age(p.days_since_activity)}\t{p.column}\t{p.name}")
        if len(stale_sorted) > show:
            out.append(f"- … and {len(stale_sorted) - show} more")
    else:
        out.append("- None")

    out.append(
        f"\nPossibly stuck in-flight (Watch/Coding/Write/Review ≥ {overdue_active_days:g} days) ({len(active_overdue_sorted)})"
    )
    if active_overdue_sorted:
        for p in active_overdue_sorted[:show]:
            out.append(f"- {_format_age(p.days_since_activity)}\t{p.column}\t{p.name}")
        if len(active_overdue_sorted) > show:
            out.append(f"- … and {len(active_overdue_sorted) - show} more")
    else:
        out.append("- None")

    out.append(f"\nPaused ({len(paused_sorted)})")
    if paused_sorted:
        for p in paused_sorted[:show]:
            out.append(f"- {_format_age(p.days_since_activity)}\t{p.name}")
        if len(paused_sorted) > show:
            out.append(f"- … and {len(paused_sorted) - show} more")
    else:
        out.append("- None")

    out.append(f"\nHygiene (missing column/workflow tag) ({len(missing_column_sorted)})")
    if missing_column_sorted:
        for p in missing_column_sorted[:show]:
            out.append(f"- {p.column}\t{p.name}\t{p.path}")
        if len(missing_column_sorted) > show:
            out.append(f"- … and {len(missing_column_sorted) - show} more")
    else:
        out.append("- None")

    return "\n".join(out).rstrip() + "\n"


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    """Parse CLI arguments."""

    parser = argparse.ArgumentParser(description="Generate a Forge kanban brief.")
    parser.add_argument("--stale-days", type=float, default=7.0, help="Threshold (days) for 'Neglected' section.")
    parser.add_argument("--show", type=int, default=15, help="Maximum items to show per non-URGENT section.")
    parser.add_argument("--urgent-show", type=int, default=25, help="Maximum URGENT items to show.")
    parser.add_argument(
        "--overdue-active-days",
        type=float,
        default=14.0,
        help="Threshold (days) for in-flight WIP (Watch/Coding/Write/Review) to flag as possibly stuck.",
    )
    parser.add_argument(
        "--calendar-days",
        type=int,
        default=3,
        help="Include Calendar.app events in the next N days (0 disables).",
    )
    parser.add_argument(
        "--calendar-warn-hours",
        type=float,
        default=24.0,
        help="Warn for events starting within this many hours (excluding today).",
    )
    parser.add_argument(
        "--calendar-timeout-seconds",
        type=float,
        default=20.0,
        help="Timeout for Calendar.app query (seconds).",
    )
    parser.add_argument(
        "--calendar-calendars",
        type=str,
        default="",
        help="Comma-separated Calendar.app calendar names to include (empty = all calendars).",
    )
    parser.add_argument(
        "--due-days",
        type=int,
        default=14,
        help="Horizon (days) for due tasks from world.db (0 disables).",
    )
    parser.add_argument(
        "--no-task-index",
        action="store_true",
        help="Skip due-task section from .forge/world.db.",
    )
    return parser.parse_args(list(argv))


def main(argv: Sequence[str]) -> int:
    """Entry point."""

    args = parse_args(argv)
    data = _run_forge_board_json()
    projects = _parse_projects(data)
    calendar_names = [s.strip() for s in (args.calendar_calendars or "").split(",") if s.strip()] or None
    brief = build_brief(
        projects=projects,
        stale_days=args.stale_days,
        show=max(1, args.show),
        urgent_show=max(1, args.urgent_show),
        overdue_active_days=args.overdue_active_days,
        calendar_days=max(0, args.calendar_days),
        calendar_warn_hours=max(0.0, args.calendar_warn_hours),
        calendar_timeout_seconds=max(0.1, args.calendar_timeout_seconds),
        calendar_names=calendar_names,
        due_days=max(0, args.due_days),
        include_task_index=not args.no_task_index and args.due_days > 0,
    )
    sys.stdout.write(brief)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))


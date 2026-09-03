"""Terminal layout renderers for the Forge dashboard."""

from __future__ import annotations

import shutil
from datetime import datetime

from .data import CalendarRow, DashboardSnapshot, DueTaskView, ProjectRow


def _term_width(default: int = 80) -> int:
    return shutil.get_terminal_size(fallback=(default, 24)).columns


def _clip(text: str, width: int) -> str:
    if len(text) <= width:
        return text
    if width <= 1:
        return text[:width]
    return text[: width - 1] + "…"


def _fmt_age(days: float) -> str:
    if days >= 30:
        return f"{days / 30:.0f}mo"
    if days >= 7:
        return f"{days:.0f}d"
    return f"{days:.1f}d"


def _fmt_event(event: CalendarRow) -> str:
    if event.all_day:
        time_s = "all-day"
    else:
        time_s = f"{event.start.strftime('%H:%M')}–{event.end.strftime('%H:%M')}"
    return f"{time_s}  {event.title}"


def _fmt_project(row: ProjectRow) -> str:
    assignee = f"  #{row.assignees[0]}" if row.assignees else ""
    return f"{_fmt_age(row.days_since_activity):>4}  {row.column:<7}  {row.name}{assignee}"


def _fmt_task(due: str, column: str | None, project: str, title: str, *, waiting: bool = False) -> str:
    suffix = " [waiting]" if waiting else ""
    col = (column or "?")[:7]
    return f"{due[:10]}  {col:<7}  {project:<28}  {_clip(title, 48)}{suffix}"


def _fmt_due(item: DueTaskView) -> str:
    return _fmt_task(
        item.due,
        item.column,
        item.project_name,
        item.title,
        waiting=item.section == "waiting",
    )


def _box(title: str, lines: list[str], *, width: int | None = None) -> list[str]:
    inner_w = (width or _term_width()) - 4
    inner_w = max(inner_w, 20)
    bar = "─" * inner_w
    out = [f"┌─ {title} {bar[len(title) + 3 :]}",]
    if not lines:
        out.append(f"│ {_clip('(none)', inner_w):<{inner_w}} │")
    else:
        for line in lines:
            out.append(f"│ {_clip(line, inner_w):<{inner_w}} │")
    out.append(f"└{'─' * (inner_w + 2)}")
    return out


def _column_summary(snap: DashboardSnapshot) -> str:
    abbrev = {
        "Watch": "Watch",
        "Coding": "Cod",
        "Write": "Write",
        "Review": "Rev",
        "Plan": "Plan",
        "Paused": "Pause",
        "Shipped": "Ship",
        "(none)": "?",
    }
    order = ("Watch", "Coding", "Write", "Review", "Plan", "Paused", "Shipped")
    parts: list[str] = []
    for name in order:
        count = snap.column_counts.get(name, 0)
        if count:
            parts.append(f"{abbrev.get(name, name[:3])}:{count}")
    active = sum(
        count
        for name, count in snap.column_counts.items()
        if name not in {"Shipped", "Paused", "(none)"}
    )
    urgent = len(snap.urgent)
    urgent_s = f"  URG:{urgent}" if urgent else ""
    return f"{' · '.join(parts)}  active:{active}{urgent_s}"


def render_tick(snap: DashboardSnapshot) -> str:
    """One-line ticker for a narrow Herdr strip."""
    stamp = snap.generated_at.strftime("%H:%M")
    overdue = len(snap.due_overdue)
    today = len(snap.due_today)
    events = len(snap.calendar_today)
    return (
        f"[{stamp}] {_column_summary(snap)}  "
        f"cal:{events}  overdue:{overdue}  due-today:{today}  "
        f"inbox:{snap.world_inbox}  index:{snap.world_open_tasks} open"
    )


def render_compact(snap: DashboardSnapshot, *, show: int = 6) -> str:
    """Single-column dashboard (~25 lines)."""
    lines: list[str] = []
    stamp = snap.generated_at.strftime("%Y-%m-%d %H:%M")
    lines.append(f"Forge dashboard  {stamp}")
    lines.append(_column_summary(snap))
    lines.append("")

    lines.extend(_box("Schedule today", [_fmt_event(event) for event in snap.calendar_today[:show]]))
    if snap.calendar_error:
        lines.append(f"  calendar: {snap.calendar_error}")
    lines.append("")

    inbox_lines = [
        f"  ☐ {item.title}" + (f"  [{item.source}]" if item.source else "")
        for item in snap.inbox[:show]
    ] or ["(empty)"]
    lines.extend(_box(f"Inbox  {snap.world_inbox} unprocessed", inbox_lines))
    lines.append("")

    task_lines: list[str] = []
    for item in snap.due_overdue[:show]:
        task_lines.append(_fmt_due(item))
    for item in snap.due_today[: max(0, show - len(task_lines))]:
        task_lines.append(_fmt_due(item))
    if not task_lines:
        task_lines.append("(no overdue / due today)")
    lines.extend(_box(f"Tasks  {snap.world_open_tasks} open", task_lines))
    if snap.world_error:
        lines.append(f"  index: {snap.world_error}")
    lines.append("")

    board_lines = [_fmt_project(row) for row in snap.urgent[:show]]
    if not board_lines:
        board_lines = [_fmt_project(row) for row in snap.stuck[:show]]
    if not board_lines:
        board_lines = ["(no URGENT or stuck items)"]
    lines.extend(_box("Board hot", board_lines))
    return "\n".join(lines)


def _half_lines(left: list[str], right: list[str], width: int) -> list[str]:
    gutter = 2
    col_w = max(28, (width - gutter) // 2)
    height = max(len(left), len(right), 1)
    out: list[str] = []
    for index in range(height):
        l = _clip(left[index] if index < len(left) else "", col_w)
        r = _clip(right[index] if index < len(right) else "", col_w)
        out.append(f"{l:<{col_w}}{' ' * gutter}{r}")
    return out


def render_split(snap: DashboardSnapshot, *, show: int = 8) -> str:
    """Two-column board | tasks layout."""
    width = _term_width()
    stamp = snap.generated_at.strftime("%Y-%m-%d %H:%M")
    header = f"Forge dashboard  {stamp}    {_column_summary(snap)}"
    lines = [header, ""]

    left_title = "BOARD"
    right_title = "TASKS"
    left = [left_title, "─" * min(32, width // 2 - 2)]
    right = [right_title, "─" * min(32, width // 2 - 2)]

    left.append("URGENT")
    left.extend(_fmt_project(row) for row in snap.urgent[:show] or [])
    if not snap.urgent:
        left.append("  (none)")
    left.append("")
    left.append("STUCK ≥14d")
    left.extend(_fmt_project(row) for row in snap.stuck[:show] or [])
    if not snap.stuck:
        left.append("  (none)")

    right.append(f"overdue ({len(snap.due_overdue)})")
    right.extend(_fmt_due(item) for item in snap.due_overdue[:show])
    right.append(f"due today ({len(snap.due_today)})")
    right.extend(_fmt_due(item) for item in snap.due_today[:show])
    right.append(f"next ({min(len(snap.due_upcoming), show)})")
    right.extend(_fmt_due(item) for item in snap.due_upcoming[:show])

    lines.extend(_half_lines(left, right, width))
    lines.append("")
    schedule = [_fmt_event(event) for event in snap.calendar_today[:show]] or ["(no events today)"]
    lines.extend(_box("Schedule", schedule, width=min(width, 120)))
    if snap.calendar_error:
        lines.append(f"calendar: {snap.calendar_error}")
    if snap.world_error:
        lines.append(f"index: {snap.world_error}")
    return "\n".join(lines)


def render_full(snap: DashboardSnapshot, *, show: int = 10) -> str:
    """Verbose single-column dashboard with all sections."""
    width = min(_term_width(), 100)
    lines: list[str] = []
    stamp = snap.generated_at.strftime("%Y-%m-%d %H:%M")
    lines.append(f"Forge GTD dashboard  {stamp}")
    lines.append(_column_summary(snap))
    lines.append(
        f"task index: {snap.world_projects} projects · {snap.world_open_tasks} open tasks · inbox {snap.world_inbox}"
    )
    lines.append("")

    lines.extend(_box("Schedule today", [_fmt_event(event) for event in snap.calendar_today[:show]]))
    lines.append("")

    inbox_lines = [f"☐ {item.title}" for item in snap.inbox[:show]]
    lines.extend(_box(f"Inbox ({snap.world_inbox})", inbox_lines or ["(empty)"], width=width))
    lines.append("")

    overdue_lines = [_fmt_due(item) for item in snap.due_overdue[:show]]
    today_lines = [_fmt_due(item) for item in snap.due_today[:show]]
    upcoming_lines = [_fmt_due(item) for item in snap.due_upcoming[:show]]
    lines.extend(_box(f"Overdue ({len(snap.due_overdue)})", overdue_lines or ["(none)"], width=width))
    lines.append("")
    lines.extend(_box(f"Due today ({len(snap.due_today)})", today_lines or ["(none)"], width=width))
    lines.append("")
    lines.extend(
        _box(f"Upcoming ({len(snap.due_upcoming)})", upcoming_lines or ["(none)"], width=width)
    )
    lines.append("")

    lines.extend(_box("URGENT", [_fmt_project(row) for row in snap.urgent[:show]] or ["(none)"], width=width))
    lines.append("")
    lines.extend(_box("Neglected", [_fmt_project(row) for row in snap.stale[:show]] or ["(none)"], width=width))
    lines.append("")
    lines.extend(_box("Stuck in-flight", [_fmt_project(row) for row in snap.stuck[:show]] or ["(none)"], width=width))

    if snap.calendar_error:
        lines.append(f"\ncalendar: {snap.calendar_error}")
    if snap.world_error:
        lines.append(f"index: {snap.world_error}")
    return "\n".join(lines)


LAYOUTS = {
    "tick": render_tick,
    "compact": render_compact,
    "split": render_split,
    "full": render_full,
}


def render(layout: str, snap: DashboardSnapshot, *, show: int = 8) -> str:
    """Render a snapshot with the named layout."""
    renderer = LAYOUTS.get(layout)
    if renderer is None:
        raise SystemExit(f"Unknown layout {layout!r}. Choose from: {', '.join(LAYOUTS)}")
    if layout == "tick":
        return renderer(snap)
    return renderer(snap, show=show)

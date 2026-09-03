"""Pretty-print project tasks for terminal reading."""

from __future__ import annotations

from datetime import date

from .toml_io import ProjectTasks, TaskRecord, SECTIONS

SECTION_LABELS = {
    "next": "Next",
    "waiting": "Waiting for",
    "done": "Done",
    "someday": "Someday maybe",
}


def _parse_day(value: str | None) -> date | None:
    """Return the calendar day from a due/defer/done string."""
    if not value:
        return None
    prefix = value.strip()[:10]
    try:
        return date.fromisoformat(prefix)
    except ValueError:
        return None


def _format_day_label(day: date, *, today: date) -> str:
    """Format a date for inline display."""
    delta = (day - today).days
    if delta == 0:
        return "today"
    if delta == 1:
        return "tomorrow"
    if delta == -1:
        return "yesterday"
    if -6 <= delta < 0:
        return day.strftime("%a %d %b")
    if 0 < delta <= 6:
        return day.strftime("%a %d %b")
    return day.isoformat()


def _format_date_field(label: str, value: str | None, *, today: date) -> str | None:
    """Return a compact due/defer/done suffix."""
    if not value:
        return None
    day = _parse_day(value)
    if day is not None:
        return f"{label} {_format_day_label(day, today=today)}"
    return f"{label} {value}"


def _format_task_line(
    task: TaskRecord,
    *,
    today: date,
    show_ids: bool = False,
    width: int = 88,
) -> str:
    """Render one task as a checklist line."""
    mark = "☑" if task.section == "done" else "☐"
    parts: list[str] = []

    if task.section == "waiting":
        parts.append("[waiting]")
    if task.flagged:
        parts.append("⚑")

    title = task.title
    if task.links:
        parts.append(f"({len(task.links)} link{'s' if len(task.links) != 1 else ''})")

    meta: list[str] = []
    for label, value in (
        ("due", task.due),
        ("defer", task.defer),
        ("done", task.done),
    ):
        formatted = _format_date_field(label, value, today=today)
        if formatted:
            meta.append(formatted)
    if task.ctx:
        meta.append("@" + ", ".join(task.ctx))
    if task.assignees:
        meta.append(" ".join(f"#{name}" for name in task.assignees))

    line = f"  {mark} {title}"
    if parts:
        line += "  " + " ".join(parts)
    if meta:
        line += "  ·  " + " · ".join(meta)
    if show_ids:
        line += f"  ({task.id})"

    if width > 0 and len(line) > width:
        return line[: width - 1] + "…"
    return line


def render_project_tasks(
    project_tasks: ProjectTasks,
    *,
    column: str | None = None,
    show_ids: bool = False,
    include_empty_sections: bool = False,
    width: int = 88,
    today: date | None = None,
) -> str:
    """Return a human-readable checklist for one project."""
    today = today or date.today()
    lines: list[str] = [project_tasks.project]
    if column:
        lines[0] += f"  ({column})"
    lines.append("")

    open_sections = [section for section in SECTIONS if project_tasks.tasks_in(section)]
    if not open_sections and not project_tasks.notes_body:
        lines.append("  (no tasks)")
        return "\n".join(lines)

    for section in SECTIONS:
        section_tasks = project_tasks.tasks_in(section)
        if not section_tasks and not include_empty_sections:
            continue
        lines.append(SECTION_LABELS.get(section, section.title()))
        if section_tasks:
            for task in section_tasks:
                lines.append(
                    _format_task_line(task, today=today, show_ids=show_ids, width=width)
                )
        else:
            lines.append("  (none)")
        lines.append("")

    if project_tasks.notes_body:
        lines.append("Notes")
        for note_line in project_tasks.notes_body.splitlines():
            lines.append(f"  {note_line.rstrip()}")
        lines.append("")

    while lines and lines[-1] == "":
        lines.pop()
    return "\n".join(lines)


def render_many(
    items: list[tuple[ProjectTasks, str | None]],
    *,
    show_ids: bool = False,
    width: int = 88,
) -> str:
    """Render several projects separated by blank lines."""
    blocks: list[str] = []
    for project_tasks, column in items:
        blocks.append(
            render_project_tasks(
                project_tasks,
                column=column,
                show_ids=show_ids,
                width=width,
            )
        )
    return "\n\n".join(blocks)

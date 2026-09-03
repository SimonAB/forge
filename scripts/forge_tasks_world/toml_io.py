"""TOML project tasks schema (`TASKS.toml` per Forge project)."""

from __future__ import annotations

import re
import tomllib
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path
from typing import Any

SCHEMA_VERSION = 1
TASKS_FILENAME = "TASKS.toml"
TASKS_RELATIVE = TASKS_FILENAME

SECTIONS = ("next", "waiting", "done", "someday")

SECTION_LABELS = {
    "next": "Next",
    "waiting": "Waiting for",
    "done": "Done",
    "someday": "Someday maybe",
}

TASKS_HEADER_LINES = (
    "# Forge project tasks. Edit in Neovim; run `forge-tasks-world.py ingest` after changes.",
    "# Mark complete with checked = true (format/ingest moves the task to [[done]]).",
)

_DATE_LITERAL = re.compile(r"^\d{4}-\d{2}-\d{2}$")


@dataclass
class TaskRecord:
    """One task row in a project's TASKS.toml."""

    id: str
    title: str
    section: str
    due: str | None = None
    defer: str | None = None
    done: str | None = None
    ctx: list[str] = field(default_factory=list)
    assignees: list[str] = field(default_factory=list)
    flagged: bool = False
    links: dict[str, str] = field(default_factory=dict)
    notes: str | None = None
    #: Transient edit flag; never written. `apply_checked_completions` moves to [[done]].
    checked: bool = False

    def fingerprint(self) -> str:
        parts = [
            self.section,
            self.title,
            self.due or "",
            self.defer or "",
            self.done or "",
            ",".join(self.ctx),
            ",".join(self.assignees),
            str(self.flagged),
        ]
        return "|".join(parts)


@dataclass
class ProjectTasks:
    """Parsed `TASKS.toml` for one Forge project."""

    project: str
    schema: int = SCHEMA_VERSION
    notes_body: str = ""
    tasks: list[TaskRecord] = field(default_factory=list)
    path: Path | None = None

    def tasks_in(self, section: str) -> list[TaskRecord]:
        return [task for task in self.tasks if task.section == section]


def _parse_task_row(section: str, row: dict[str, Any]) -> TaskRecord:
    links = {key: str(value) for key, value in row.items() if key.startswith("links.")}
    clean_links = {key.removeprefix("links."): value for key, value in links.items()}
    if "links" in row and isinstance(row["links"], dict):
        for key, value in row["links"].items():
            clean_links[str(key)] = str(value)

    ctx = row.get("ctx") or []
    if isinstance(ctx, str):
        ctx = [ctx]

    assignees = row.get("assignees") or []
    if isinstance(assignees, str):
        assignees = [assignees]

    task_id = str(row.get("id") or "").strip()
    if not task_id:
        raise ValueError(f"task in section '{section}' is missing id")

    title = str(row.get("title") or "").strip()
    if not title:
        raise ValueError(f"task {task_id} is missing title")

    return TaskRecord(
        id=task_id,
        title=title,
        section=section,
        due=_optional_str(row.get("due")),
        defer=_optional_str(row.get("defer")),
        done=_optional_str(row.get("done")),
        ctx=[str(item) for item in ctx],
        assignees=[str(item) for item in assignees],
        flagged=bool(row.get("flagged", False)),
        links=clean_links,
        notes=_optional_str(row.get("notes")),
        checked=bool(row.get("checked", False)),
    )


def apply_checked_completions(
    project_tasks: ProjectTasks,
    *,
    today: date | None = None,
) -> bool:
    """
    Move tasks with ``checked = true`` into ``[[done]]``.

    Sets ``done`` to today when missing, clears the transient ``checked`` flag.
    Returns True when any task changed (caller should rewrite TASKS.toml).
    """
    day = (today or date.today()).isoformat()
    changed = False
    for task in project_tasks.tasks:
        if not task.checked:
            continue
        changed = True
        if task.section != "done":
            task.section = "done"
            if not task.done:
                task.done = day
        task.checked = False
    return changed


def upsert_task(project_tasks: ProjectTasks, task: TaskRecord) -> None:
    """Replace a task by id, or append when new."""
    remaining = [item for item in project_tasks.tasks if item.id != task.id]
    remaining.append(task)
    project_tasks.tasks = remaining


def _optional_str(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, date):
        return value.isoformat()
    text = str(value).strip()
    return text or None


def _toml_quote_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def _toml_scalar(value: str) -> str:
    """Emit a bare date or quoted string as appropriate."""
    stripped = value.strip()
    if _DATE_LITERAL.fullmatch(stripped[:10]):
        return stripped[:10]
    return _toml_quote_string(value)


def _toml_multiline_string(value: str) -> str:
    """Use a multiline basic string for long or multiline text."""
    if "\n" not in value and len(value) <= 72:
        return _toml_quote_string(value)
    escaped = value.replace("\\", "\\\\").replace('"""', '\\"""')
    return f'"""\n{escaped}\n"""'


def _toml_inline_array(items: list[str]) -> str:
    inner = ", ".join(_toml_quote_string(item) for item in items)
    return f"[{inner}]"


def load_project_tasks(path: Path) -> ProjectTasks:
    """Load project tasks from TOML."""
    data = tomllib.loads(path.read_text(encoding="utf-8"))
    meta = data.get("meta") or {}
    project = str(meta.get("project") or path.parent.parent.name)
    schema = int(meta.get("schema") or SCHEMA_VERSION)

    notes = data.get("notes") or {}
    notes_body = str(notes.get("body") or "").strip()

    tasks: list[TaskRecord] = []
    for section in SECTIONS:
        for row in data.get(section) or []:
            if not isinstance(row, dict):
                continue
            tasks.append(_parse_task_row(section, row))

    return ProjectTasks(
        project=project,
        schema=schema,
        notes_body=notes_body,
        tasks=tasks,
        path=path,
    )


load_leaf = load_project_tasks


def write_project_tasks(project_tasks: ProjectTasks, path: Path) -> None:
    """Write project tasks as human-friendly TOML."""
    lines: list[str] = [
        *TASKS_HEADER_LINES,
        "",
        "[meta]",
        f"schema = {project_tasks.schema}",
        f"project = {_toml_quote_string(project_tasks.project)}",
        "",
    ]

    for section in SECTIONS:
        section_tasks = project_tasks.tasks_in(section)
        if not section_tasks:
            continue
        lines.append(f"# {SECTION_LABELS.get(section, section.title())}")
        for task in section_tasks:
            lines.append(f"[[{section}]]")
            lines.append(f"title = {_toml_quote_string(task.title)}")
            for key in ("due", "defer", "done"):
                value = getattr(task, key)
                if value:
                    lines.append(f"{key} = {_toml_scalar(value)}")
            if task.flagged:
                lines.append("flagged = true")
            if task.ctx:
                lines.append(f"ctx = {_toml_inline_array(task.ctx)}")
            if task.assignees:
                lines.append(f"assignees = {_toml_inline_array(task.assignees)}")
            if task.links:
                links_parts = ", ".join(
                    f"{key} = {_toml_quote_string(value)}"
                    for key, value in task.links.items()
                )
                lines.append(f"links = {{ {links_parts} }}")
            if task.notes:
                lines.append(f"notes = {_toml_multiline_string(task.notes)}")
            lines.append(f'id = "{task.id}"  # Forge-assigned; do not edit')
            lines.append("")

    if project_tasks.notes_body:
        lines.extend(
            [
                "[notes]",
                f"body = {_toml_multiline_string(project_tasks.notes_body)}",
                "",
            ]
        )

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")


write_leaf = write_project_tasks


def project_tasks_path(project_dir: Path) -> Path:
    """Return the canonical TASKS.toml path for a Forge project directory."""
    return project_dir / TASKS_RELATIVE


leaf_path_for_project = project_tasks_path


def ensure_project_tasks(project_dir: Path, project_name: str) -> Path:
    """Create an empty TASKS.toml when the board project has no tasks file yet."""
    toml_path = project_tasks_path(project_dir)
    if toml_path.exists():
        return toml_path
    write_project_tasks(ProjectTasks(project=project_name, tasks=[]), toml_path)
    return toml_path


ensure_board_leaf = ensure_project_tasks

# Legacy names (pre project/tasks terminology)
LEAF_FILENAME = TASKS_FILENAME
LEAF_RELATIVE = TASKS_RELATIVE
TaskLeaf = ProjectTasks

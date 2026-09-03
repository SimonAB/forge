"""Convert legacy TASKS.md into per-project TASKS.toml."""

from __future__ import annotations

import re
from pathlib import Path

from .toml_io import (
    SCHEMA_VERSION,
    ProjectTasks,
    TaskRecord,
    load_project_tasks,
    write_project_tasks,
)

TASK_LINE = re.compile(
    r"^- \[(?P<mark>[ xX])\]\s+(?P<body>.+?)(?:\s+<!--\s*id:(?P<id>[^>]+?)\s*-->)?\s*$"
)
LINK_BODY = re.compile(r"^\[(?P<title>.+?)\]\((?P<link>[^)]+)\)\s*$")
TAG = re.compile(r"@(?P<name>[a-zA-Z_-]+)\((?P<value>[^)]*)\)")
SECTION_HEADING = re.compile(r"^##\s+(?P<section>.+?)\s*$")


def _normalise_section(name: str) -> str | None:
    lowered = name.strip().lower()
    if lowered == "next actions":
        return "next"
    if lowered == "waiting for":
        return "waiting"
    if lowered == "completed":
        return "done"
    if lowered in {"notes", "note"}:
        return "notes"
    if lowered == "someday maybe":
        return "someday"
    return None


def _parse_tags(body: str) -> tuple[str, dict[str, str | list[str] | bool]]:
    tags: dict[str, str | list[str] | bool] = {}
    cleaned = body

    for match in TAG.finditer(body):
        name = match.group("name")
        value = match.group("value").strip()
        if name in {"ctx", "context"}:
            tags.setdefault("ctx", []).append(value)
        elif name == "person":
            tags.setdefault("assignees", []).append(value.lstrip("#"))
        elif name in {"due", "defer", "done"}:
            tags[name] = value
        elif name == "flagged":
            tags["flagged"] = True
        cleaned = cleaned.replace(match.group(0), " ")

    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    return cleaned, tags


def _parse_body(body: str) -> tuple[str, dict[str, str]]:
    link_match = LINK_BODY.match(body.strip())
    if link_match:
        title = link_match.group("title").strip()
        link = link_match.group("link").strip()
        links = {"mail": link} if link.startswith("message:") else {"url": link}
        return title, links
    return body.strip(), {}


def convert_tasks_md_to_project_tasks(md_path: Path) -> ProjectTasks:
    """Parse a TASKS.md file into project tasks."""
    text = md_path.read_text(encoding="utf-8")
    lines = text.splitlines()

    project_name = md_path.parent.name
    if lines and lines[0].startswith("# "):
        project_name = lines[0][2:].strip() or project_name

    section = "next"
    notes_lines: list[str] = []
    in_notes = False
    tasks: list[TaskRecord] = []

    for raw_line in lines[1:]:
        line = raw_line.rstrip()
        heading = SECTION_HEADING.match(line)
        if heading:
            mapped = _normalise_section(heading.group("section"))
            if mapped == "notes":
                in_notes = True
                continue
            in_notes = False
            if mapped:
                section = mapped
            continue

        if in_notes:
            if line.strip():
                notes_lines.append(line.strip())
            continue

        match = TASK_LINE.match(line)
        if not match:
            continue

        body = match.group("body").strip()
        task_id = (match.group("id") or "").strip()
        if not task_id:
            raise ValueError(f"{md_path}: task line missing id: {line}")

        tagged_body, tags = _parse_tags(body)
        title, links = _parse_body(tagged_body)
        assignees = tags.get("assignees") or []
        if isinstance(assignees, str):
            assignees = [assignees]
        ctx = tags.get("ctx") or []
        if isinstance(ctx, str):
            ctx = [ctx]

        mapped_section = "done" if match.group("mark").lower() == "x" else section
        if mapped_section not in {"next", "waiting", "done", "someday"}:
            mapped_section = "next"

        tasks.append(
            TaskRecord(
                id=task_id,
                title=title,
                section=mapped_section,
                due=_optional(tags.get("due")),
                defer=_optional(tags.get("defer")),
                done=_optional(tags.get("done")),
                ctx=[str(item) for item in ctx],
                assignees=[str(item).lstrip("#") for item in assignees],
                flagged=bool(tags.get("flagged", False)),
                links=links,
            )
        )

    return ProjectTasks(
        project=project_name,
        schema=SCHEMA_VERSION,
        notes_body="\n".join(notes_lines).strip(),
        tasks=tasks,
        path=md_path,
    )


convert_tasks_md_to_leaf = convert_tasks_md_to_project_tasks


def _optional(value: object | None) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def convert_tasks_md_file(md_path: Path, toml_path: Path) -> ProjectTasks:
    """Convert TASKS.md to `TASKS.toml`, preserving existing TOML ids when possible."""
    project_tasks = convert_tasks_md_to_project_tasks(md_path)
    if toml_path.exists():
        existing = load_project_tasks(toml_path)
        if existing.notes_body and not project_tasks.notes_body:
            project_tasks.notes_body = existing.notes_body
    write_project_tasks(project_tasks, toml_path)
    project_tasks.path = toml_path
    return project_tasks

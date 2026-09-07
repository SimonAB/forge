#!/usr/bin/env python3
"""Portable Forge kanban sidecar used to exchange state between OSes."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
import tomllib


SIDECAR_REL = Path(".forge") / "kanban.toml"


@dataclass(frozen=True)
class KanbanSidecar:
    column: str | None
    workflow_tag: str | None
    meta: tuple[str, ...]
    assignees: tuple[str, ...]
    updated_at: str
    source: str
    schema: int = 1


def path_for(folder: Path) -> Path:
    return folder / SIDECAR_REL


def load(folder: Path) -> KanbanSidecar | None:
    path = path_for(folder)
    if not path.is_file():
        return None
    try:
        raw = tomllib.loads(path.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError):
        return None
    return KanbanSidecar(
        column=_as_text(raw.get("column")),
        workflow_tag=_as_text(raw.get("workflow_tag")),
        meta=tuple(_as_strings(raw.get("meta"))),
        assignees=tuple(_normalise_assignee(value) for value in _as_strings(raw.get("assignees"))),
        updated_at=_as_text(raw.get("updated_at")) or "",
        source=_as_text(raw.get("source")) or "migrate",
        schema=int(raw.get("schema") or 1),
    )


def save(folder: Path, sidecar: KanbanSidecar) -> Path:
    path = path_for(folder)
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [f"schema = {sidecar.schema}"]
    if sidecar.column:
        lines.append(f"column = {_quote(sidecar.column)}")
    if sidecar.workflow_tag:
        lines.append(f"workflow_tag = {_quote(sidecar.workflow_tag)}")
    lines.extend([
        f"meta = {_array(sidecar.meta)}",
        f"assignees = {_array(sidecar.assignees)}",
        f"updated_at = {_quote(sidecar.updated_at or now())}",
        f"source = {_quote(sidecar.source)}",
        "",
    ])
    path.write_text("\n".join(lines), encoding="utf-8")
    return path


def now() -> str:
    return datetime.now(UTC).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _as_text(value: object) -> str | None:
    return value.strip() if isinstance(value, str) and value.strip() else None


def _as_strings(value: object) -> list[str]:
    return [item.strip() for item in value if isinstance(item, str) and item.strip()] if isinstance(value, list) else []


def _normalise_assignee(value: str) -> str:
    return value if value.startswith("#") else f"#{value}"


def _quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _array(values: tuple[str, ...]) -> str:
    return "[" + ", ".join(_quote(value) for value in values) + "]"

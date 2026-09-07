"""Small, dependency-free model and client for the Linux Forge board window."""

from __future__ import annotations

import json
import os
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable


@dataclass(frozen=True)
class BoardProject:
    name: str
    path: str
    column: str
    meta_tags: tuple[str, ...] = ()
    urgent: bool = False


@dataclass(frozen=True)
class BoardColumn:
    name: str
    tag: str
    colour: int = 0


@dataclass(frozen=True)
class BoardSnapshot:
    columns: tuple[BoardColumn, ...]
    projects: tuple[BoardProject, ...]
    sp_projects: int = 0
    sp_open_tasks: int = 0
    sp_inbox: int = 0
    sp_error: str | None = None
    calendar_error: str | None = None
    generated_at: str | None = None

    @property
    def by_column(self) -> dict[str, tuple[BoardProject, ...]]:
        return {
            column.name: tuple(project for project in self.projects if project.column == column.name)
            for column in self.columns
        }


def snapshot_from_json(board: dict[str, Any], dashboard: dict[str, Any] | None = None) -> BoardSnapshot:
    """Convert the stable CLI/dashboard JSON surfaces into UI data."""
    dashboard = dashboard or {}
    raw_board = board.get("board") or {}
    columns = tuple(
        BoardColumn(str(item.get("name") or ""), str(item.get("tag") or ""), int(item.get("colour") or 0))
        for item in raw_board.get("columns") or []
        if item.get("name")
    )
    projects = tuple(
        BoardProject(
            name=str(item.get("name") or ""),
            path=str(item.get("path") or ""),
            column=str(item.get("column") or "(none)"),
            meta_tags=tuple(str(tag) for tag in item.get("metaTags") or []),
            urgent=any(str(tag).upper().startswith("URGENT") for tag in item.get("metaTags") or []),
        )
        for item in board.get("projects") or []
        if item.get("name")
    )
    world = dashboard.get("world") or {}
    return BoardSnapshot(
        columns=columns,
        projects=projects,
        sp_projects=int(world.get("projects") or 0),
        sp_open_tasks=int(world.get("open_tasks") or 0),
        sp_inbox=int(world.get("inbox") or 0),
        sp_error=world.get("error"),
        calendar_error=dashboard.get("calendar_error"),
        generated_at=dashboard.get("generated_at"),
    )


class ForgeBoardClient:
    """Read Forge state through the public CLI; no xattrs are touched here."""

    def __init__(self, forge_home: Path | None = None, forge_bin: str | None = None,
                 runner: Callable[..., subprocess.CompletedProcess[str]] | None = None) -> None:
        self.forge_home = forge_home or Path(os.environ.get("FORGE_HOME", "")).expanduser()
        if not str(self.forge_home):
            self.forge_home = Path.cwd()
        self.forge_bin = forge_bin or os.environ.get("FORGE_BIN", "forge")
        self.runner = runner or subprocess.run

    def _run_json(self, *args: str) -> dict[str, Any]:
        result = self.runner(
            [self.forge_bin, *args],
            cwd=self.forge_home,
            text=True,
            capture_output=True,
            check=False,
        )
        if result.returncode:
            detail = (result.stderr or result.stdout or "command failed").strip()
            raise RuntimeError(detail)
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError as exc:
            raise RuntimeError(f"forge returned invalid JSON: {exc}") from exc

    def refresh(self) -> BoardSnapshot:
        board = self._run_json("board", "--json")
        # Dashboard enriches the board with SP/calendar counters. It is allowed
        # to fail: the board remains useful when a task backend is unavailable.
        try:
            dashboard = self._run_json("dashboard", "--json")
        except RuntimeError as exc:
            dashboard = {"world": {"error": str(exc)}}
        return snapshot_from_json(board, dashboard)

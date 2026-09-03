"""GTD capture into the Forge task database (inbox-first)."""

from __future__ import annotations

import json
import re
import secrets
import shutil
from dataclasses import dataclass
from pathlib import Path
import subprocess

from .world_db import WorldDatabase

LINK_KINDS = ("mail", "file", "url", "note", "obsidian", "bookends", "other")
SOURCES = ("cli", "menubar", "assistant", "service", "import", "toml")

_MESSAGE_URI = re.compile(r"^message:", re.IGNORECASE)
_HTTP_URI = re.compile(r"^https?://", re.IGNORECASE)
_FILE_URI = re.compile(r"^file:", re.IGNORECASE)
_OBSIDIAN_URI = re.compile(r"^obsidian:", re.IGNORECASE)


@dataclass
class CapturedItem:
    """Result of a successful inbox capture."""

    task_id: str
    title: str
    section: str
    source: str
    links: list[dict[str, str]]
    notes: str | None
    created_at: str


@dataclass
class InboxItem:
    """One inbox row for listing."""

    task_id: str
    title: str
    source: str | None
    created_at: str | None
    notes: str | None
    links: list[dict[str, str]]


def new_task_id() -> str:
    """Return a Forge-assigned opaque task id."""
    return secrets.token_urlsafe(9).rstrip("=")


def infer_link_kind(uri: str) -> str:
    """Guess link kind from a URI."""
    text = uri.strip()
    if _MESSAGE_URI.match(text):
        return "mail"
    if _FILE_URI.match(text):
        return "file"
    if _OBSIDIAN_URI.match(text):
        return "obsidian"
    if _HTTP_URI.match(text):
        return "url"
    if text.startswith("/") or re.match(r"^[A-Za-z]:[\\/]", text):
        return "file"
    return "other"


def path_to_file_uri(path: Path) -> str:
    """Return a file:// URI for an absolute path."""
    return path.resolve().as_uri()


def sniff_clipboard_link(text: str) -> tuple[str, str] | None:
    """
    If clipboard text looks like a single URI, return (kind, uri).

    Otherwise return None.
    """
    candidate = text.strip()
    if not candidate or "\n" in candidate:
        return None
    if " " in candidate and not candidate.startswith("message:"):
        return None
    kind = infer_link_kind(candidate)
    if kind == "other" and not candidate.startswith(("bookends:", "x-bookends:")):
        if not re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", candidate):
            return None
        kind = "other"
    if kind == "file" and not candidate.startswith("file:"):
        path = Path(candidate).expanduser()
        if path.exists():
            return ("file", path_to_file_uri(path))
        return None
    return (kind, candidate)


MAIL_SELECTION_JXA = r"""
function run() {
  var Mail = Application("Mail");
  var sel;
  try { sel = Mail.selection(); } catch (e) { return "[]"; }
  if (!sel || !sel.length) return "[]";
  var rows = [];
  for (var i = 0; i < sel.length; i++) {
    var m = sel[i];
    var subject = "";
    var mid = "";
    try { subject = m.subject() || ""; } catch (e) {}
    try { mid = m.messageId() || ""; } catch (e) {}
    rows.push({ title: subject, message_id: mid });
  }
  return JSON.stringify(rows);
}
"""


def message_uri(message_id: str) -> str:
    """Build a message:// URI from a Mail message-id."""
    mid = message_id.strip().strip("<>")
    if not mid:
        return ""
    return f"message://%3c{mid}%3e"


def selected_mail_messages() -> list[dict[str, str]]:
    """Return selected Mail.app messages as {title, uri} dicts."""
    result = subprocess.run(
        ["osascript", "-l", "JavaScript", "-e", MAIL_SELECTION_JXA],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError((result.stderr or result.stdout or "Mail selection failed").strip())
    raw = (result.stdout or "").strip() or "[]"
    try:
        rows = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Mail selection returned invalid JSON: {raw}") from exc
    items: list[dict[str, str]] = []
    for row in rows:
        title = str(row.get("title") or "Mail message").strip() or "Mail message"
        uri = message_uri(str(row.get("message_id") or ""))
        items.append({"title": title, "uri": uri})
    return items


def task_db_path(forge_home: Path) -> Path:
    """
    Return the canonical task database path.

    Prefers `.forge/tasks.db`. If only legacy `world.db` exists, rename it.
    """
    forge_dir = forge_home / ".forge"
    forge_dir.mkdir(parents=True, exist_ok=True)
    tasks = forge_dir / "tasks.db"
    world = forge_dir / "world.db"
    if tasks.exists():
        return tasks
    if world.exists():
        world.rename(tasks)
        return tasks
    return tasks


class CaptureStore:
    """Write/read inbox captures against the task database."""

    def __init__(self, forge_home: Path) -> None:
        self.forge_home = forge_home
        self.db_path = task_db_path(forge_home)
        self.db = WorldDatabase(self.db_path)
        self.inbox_dir = forge_home / ".forge" / "inbox"

    def close(self) -> None:
        self.db.close()

    def capture(
        self,
        title: str,
        *,
        link: str | None = None,
        kind: str | None = None,
        note: str | None = None,
        file_path: Path | None = None,
        stash: bool = False,
        source: str = "cli",
    ) -> CapturedItem:
        """Insert an inbox item; link-only unless stash is requested for a file."""
        clean_title = title.strip()
        if not clean_title:
            raise ValueError("capture title must not be empty")

        source_key = source.strip().lower() or "cli"
        if source_key not in SOURCES:
            source_key = "cli"

        task_id = new_task_id()
        links: list[dict[str, str]] = []
        notes = (note or "").strip() or None

        resolved_file: Path | None = None
        if file_path is not None:
            resolved_file = file_path.expanduser().resolve()
            if not resolved_file.exists():
                raise FileNotFoundError(f"file not found: {resolved_file}")

        uri = (link or "").strip() or None
        link_kind = (kind or "").strip().lower() or None

        if resolved_file is not None:
            if stash:
                stashed = self._stash_file(task_id, resolved_file)
                uri = path_to_file_uri(stashed)
            else:
                uri = path_to_file_uri(resolved_file)
            link_kind = "file"

        if uri:
            if link_kind is None or link_kind not in LINK_KINDS:
                link_kind = infer_link_kind(uri)
            if link_kind == "file" and not uri.startswith("file:"):
                path = Path(uri).expanduser()
                if path.exists():
                    uri = path_to_file_uri(path)
            links.append({"kind": link_kind, "uri": uri})

        created = self.db.capture_inbox(
            task_id=task_id,
            title=clean_title,
            source=source_key,
            notes=notes,
            links=links,
        )
        return CapturedItem(
            task_id=created["id"],
            title=created["title"],
            section=created["section"],
            source=created["source"],
            links=links,
            notes=notes,
            created_at=created["created_at"],
        )

    def list_inbox(self) -> list[InboxItem]:
        """Return all open inbox items, oldest first."""
        rows = self.db.list_inbox()
        items: list[InboxItem] = []
        for row in rows:
            links = json.loads(row["links"] or "[]")
            if isinstance(links, dict):
                links = [
                    {"kind": key, "uri": str(value)} for key, value in links.items()
                ]
            items.append(
                InboxItem(
                    task_id=row["id"],
                    title=row["title"],
                    source=row["source"],
                    created_at=row["created_at"],
                    notes=row["notes"],
                    links=links if isinstance(links, list) else [],
                )
            )
        return items

    def assign(
        self,
        task_id: str,
        project_path: Path,
        project_name: str,
        *,
        section: str = "next",
        column_name: str | None = None,
    ) -> None:
        """Move an inbox item onto a Forge project."""
        if section not in {"next", "waiting", "someday"}:
            raise ValueError(f"invalid section for assign: {section}")
        self.db.assign_task(
            task_id=task_id,
            project_path=project_path,
            project_name=project_name,
            section=section,
            column_name=column_name,
        )

    def complete(self, task_id: str) -> None:
        """Mark a task done."""
        self.db.complete_task(task_id)

    def get_open_link(self, task_id: str) -> str | None:
        """Return the first openable URI for a task, if any."""
        row = self.db.get_task(task_id)
        if row is None:
            return None
        links = json.loads(row["links"] or "[]")
        if isinstance(links, dict):
            for value in links.values():
                return str(value)
        if isinstance(links, list):
            for item in links:
                if isinstance(item, dict) and item.get("uri"):
                    return str(item["uri"])
        return None

    def _stash_file(self, task_id: str, source: Path) -> Path:
        """Copy a file into `.forge/inbox/<id>/` and return the destination path."""
        dest_dir = self.inbox_dir / task_id
        dest_dir.mkdir(parents=True, exist_ok=True)
        dest = dest_dir / source.name
        if dest.exists():
            stem = source.stem
            suffix = source.suffix
            dest = dest_dir / f"{stem}-{secrets.token_hex(3)}{suffix}"
        shutil.copy2(source, dest)
        return dest

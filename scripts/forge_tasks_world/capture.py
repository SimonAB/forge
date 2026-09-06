"""GTD capture into the Forge task database (inbox-first)."""

from __future__ import annotations

import hashlib
import json
import re
import secrets
import shutil
from dataclasses import dataclass
from pathlib import Path
import subprocess
from urllib.parse import quote, urlparse, unquote

from .world_db import WorldDatabase
from .toml_io import (
    TaskRecord,
    apply_checked_completions,
    ensure_project_tasks,
    load_project_tasks,
    project_tasks_path,
    upsert_task,
    write_project_tasks,
)

LINK_KINDS = ("mail", "file", "url", "note", "obsidian", "bookends", "other")
SOURCES = ("cli", "menubar", "assistant", "service", "import", "toml")

_MESSAGE_URI = re.compile(r"^message:", re.IGNORECASE)
_HTTP_URI = re.compile(r"^https?://", re.IGNORECASE)
_FILE_URI = re.compile(r"^file:", re.IGNORECASE)
_OBSIDIAN_URI = re.compile(r"^obsidian:", re.IGNORECASE)
_MD_LINK_RE = re.compile(r"\[([^\]]*)\]\(([^)\s]+)\)")
_ANGLE_URI_RE = re.compile(r"<((?:https?|message|file|obsidian|bookends|x-bookends):[^>\s]+)>", re.I)
_BARE_URI_RE = re.compile(
    r"^((?:https?|message|file|obsidian|bookends|x-bookends):[^\s]+)\s*$",
    re.I,
)
_FORGE_URI_RE = re.compile(r"\[forge:uri:([^\]]+)\]", re.IGNORECASE)
_WEBLOC_URL_RE = re.compile(
    r"<key>\s*URL\s*</key>\s*<string>([^<]+)</string>",
    re.IGNORECASE | re.DOTALL,
)


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
    """Build a ``message://`` URI from a Mail message-id.

    Encodes the id as ``message://%3c…%3e`` so Apple Mail and Forge agree.
    """
    mid = message_id.strip().strip("<>")
    if not mid:
        return ""
    # Keep @ . + - _ = unencoded (Mail / common message-id shape); encode the rest.
    encoded_mid = quote(mid, safe="@.+-_=")
    return f"message://%3c{encoded_mid}%3e"


def normalize_mail_uri(uri: str) -> str:
    """Normalise OmniFocus ``message:…`` forms to ``message://…`` for Mail."""
    text = (uri or "").strip()
    lower = text.lower()
    if lower.startswith("message://"):
        return text
    if lower.startswith("message:"):
        return "message://" + text[len("message:") :].lstrip("/")
    return text


def format_sp_uri_marker(uri: str) -> str:
    """Return a Forge marker that stores the canonical open URI in SP notes."""
    return f"[forge:uri:{(uri or '').strip()}]"


def mail_open_link_path(forge_home: Path, mail_uri: str) -> Path:
    """Return the stable internet-location path for a Mail message URI."""
    digest = hashlib.sha256(normalize_mail_uri(mail_uri).encode("utf-8")).hexdigest()[:16]
    # ``.inetloc`` (not ``.webloc``): Launch Services opens message:// only via inetloc.
    return forge_home / ".forge" / "mail-open" / f"{digest}.inetloc"


def ensure_mail_open_link(forge_home: Path, mail_uri: str) -> Path:
    """Write (or reuse) a macOS internet-location trampoline for ``message://``.

    Super Productivity blocks the ``message://`` scheme in notes ("unsafe URL
    scheme"). ``file://`` is allowed; opening the ``.inetloc`` hands the real
    Mail URI to the OS. Plain ``.webloc`` files fail for ``message://``.
    """
    clean = normalize_mail_uri(mail_uri)
    if not clean.lower().startswith("message:"):
        raise ValueError(f"not a Mail message URI: {mail_uri!r}")
    path = mail_open_link_path(forge_home, clean)
    path.parent.mkdir(parents=True, exist_ok=True)
    body = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
        '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
        '<plist version="1.0">\n'
        "<dict>\n"
        "\t<key>URL</key>\n"
        f"\t<string>{clean}</string>\n"
        "</dict>\n"
        "</plist>\n"
    )
    if not path.is_file() or path.read_text(encoding="utf-8") != body:
        path.write_text(body, encoding="utf-8")
    return path


def uri_from_internet_location(path: Path) -> str | None:
    """Read the URL string from a ``.inetloc`` / ``.webloc`` plist, if present."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return None
    match = _WEBLOC_URL_RE.search(text)
    return match.group(1).strip() if match else None


def format_sp_note_link(
    uri: str,
    *,
    kind: str | None = None,
    label: str | None = None,
) -> str:
    """Return a markdown link line that SP notes parse as a clickable URL.

    Bare ``https://`` forms with punctuation can break SP's markdown autolinker;
    wrapping as ``[label](uri)`` is reliable. Parentheses inside the URI are
    percent-encoded so the markdown parser does not truncate.

    Do **not** pass ``message://`` here for clickable SP notes — SP blocks that
    scheme. Use :func:`format_sp_note_attachment` instead (``.inetloc`` trampoline).
    """
    clean = (uri or "").strip()
    if not clean:
        return ""
    inferred = kind or infer_link_kind(clean)
    if label is None:
        if inferred == "mail" or clean.lower().startswith("message:"):
            label = "Open in Mail"
        elif inferred == "file" or clean.lower().startswith("file:"):
            label = "Open file"
        elif inferred == "url":
            parsed = urlparse(clean)
            label = parsed.netloc or "Open link"
        elif inferred == "obsidian":
            label = "Open in Obsidian"
        else:
            label = "Open link"
    safe_label = label.replace("]", "\\]")
    # Keep scheme + structure; encode ')' so markdown ``](…)`` stays balanced.
    safe_uri = clean.replace(")", "%29").replace(" ", "%20")
    return f"[{safe_label}]({safe_uri})"


def format_sp_note_attachment(
    uri: str,
    *,
    kind: str | None = None,
    forge_home: Path | None = None,
    label: str | None = None,
) -> list[str]:
    """Return SP note lines for a link that stays clickable in Super Productivity.

    Mail URIs use a local ``.inetloc`` (``file://``) plus ``[forge:uri:…]`` so
    ``forge tasks open`` still receives the real ``message://`` target.
    """
    clean = (uri or "").strip()
    if not clean:
        return []
    inferred = kind or infer_link_kind(clean)
    is_mail = inferred == "mail" or clean.lower().startswith("message:")
    if is_mail and forge_home is not None:
        mail = normalize_mail_uri(clean)
        location = ensure_mail_open_link(forge_home, mail)
        click = format_sp_note_link(
            location.resolve().as_uri(),
            kind="file",
            label=label or "Open in Mail",
        )
        return [click, format_sp_uri_marker(mail)]
    if is_mail:
        # No Forge home (tests / dry paths): keep the URI for open, not for SP click.
        mail = normalize_mail_uri(clean)
        return [format_sp_uri_marker(mail), mail]
    return [format_sp_note_link(clean, kind=inferred, label=label)]


def extract_uri_from_notes(notes: str | None) -> str | None:
    """Return the first openable URI embedded in notes.

    Prefers ``[forge:uri:…]`` (canonical Mail target), then markdown / angle /
    bare URIs. Resolves Forge mail ``.inetloc`` trampolines back to ``message://``.
    """
    if not notes:
        return None
    marker = _FORGE_URI_RE.search(notes)
    if marker:
        return marker.group(1).strip()

    for line in notes.splitlines():
        text = line.strip()
        if not text:
            continue
        match = _MD_LINK_RE.search(text)
        if match:
            candidate = match.group(2).strip().replace("%29", ")")
            if (
                "://" in candidate
                or candidate.lower().startswith(("message:", "file:", "obsidian:"))
            ):
                resolved = _resolve_extracted_uri(candidate)
                if resolved:
                    return resolved
        match = _ANGLE_URI_RE.search(text)
        if match:
            resolved = _resolve_extracted_uri(match.group(1).strip())
            if resolved:
                return resolved
        match = _BARE_URI_RE.match(text)
        if match:
            resolved = _resolve_extracted_uri(match.group(1).strip())
            if resolved:
                return resolved
        if text.startswith(("http://", "https://", "file:", "message:", "obsidian:")):
            resolved = _resolve_extracted_uri(text.split()[0])
            if resolved:
                return resolved
    return None


def _resolve_extracted_uri(uri: str) -> str | None:
    """Map trampoline ``file://…mail-open/*`` back to ``message://``."""
    clean = (uri or "").strip()
    if not clean:
        return None
    if clean.lower().startswith("message:"):
        return normalize_mail_uri(clean)
    if clean.lower().startswith("file:"):
        parsed = urlparse(clean)
        path = Path(unquote(parsed.path))
        if path.suffix.lower() in {".inetloc", ".webloc"} and "mail-open" in path.parts:
            from_loc = uri_from_internet_location(path)
            if from_loc:
                return normalize_mail_uri(from_loc)
        return clean
    return clean


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
        """Move an inbox item onto a Forge project and write TASKS.toml."""
        if section not in {"next", "waiting", "someday"}:
            raise ValueError(f"invalid section for assign: {section}")
        self.db.assign_task(
            task_id=task_id,
            project_path=project_path,
            project_name=project_name,
            section=section,
            column_name=column_name,
        )
        self._sync_task_to_project_toml(task_id)

    def complete(self, task_id: str) -> None:
        """Mark a task done in the index and in TASKS.toml when project-linked."""
        self.db.complete_task(task_id)
        self._sync_task_to_project_toml(task_id)

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

    def _sync_task_to_project_toml(self, task_id: str) -> None:
        """Upsert one DB task into its project's TASKS.toml and refresh the index row fingerprint."""
        row = self.db.get_task(task_id)
        if row is None:
            return
        project_path_raw = row["project_path"]
        if not project_path_raw:
            return
        project_path = Path(str(project_path_raw))
        project_name = self._project_name_for_path(project_path) or project_path.name
        column_name = self._project_column_for_path(project_path)

        ensure_project_tasks(project_path, project_name)
        toml_path = project_tasks_path(project_path)
        project_tasks = load_project_tasks(toml_path)
        apply_checked_completions(project_tasks)
        upsert_task(project_tasks, self._task_record_from_row(row))
        write_project_tasks(project_tasks, toml_path)

        # Re-ingest so the index fingerprint matches the rewritten file.
        refreshed = load_project_tasks(toml_path)
        self.db.ingest_project(
            project_path=project_path,
            project_name=project_name,
            column_name=column_name,
            project_tasks=refreshed,
            tasks_path=toml_path,
        )

    def _project_name_for_path(self, project_path: Path) -> str | None:
        row = self.db.conn.execute(
            "SELECT name FROM projects WHERE path = ?",
            (str(project_path),),
        ).fetchone()
        return str(row["name"]) if row and row["name"] else None

    def _project_column_for_path(self, project_path: Path) -> str | None:
        row = self.db.conn.execute(
            "SELECT column_name FROM projects WHERE path = ?",
            (str(project_path),),
        ).fetchone()
        if row and row["column_name"]:
            return str(row["column_name"])
        return None

    @staticmethod
    def _task_record_from_row(row) -> TaskRecord:
        """Build a TaskRecord from a tasks table row."""
        links_raw = json.loads(row["links"] or "[]")
        links: dict[str, str] = {}
        if isinstance(links_raw, dict):
            links = {str(key): str(value) for key, value in links_raw.items()}
        elif isinstance(links_raw, list):
            for item in links_raw:
                if isinstance(item, dict) and item.get("uri"):
                    kind = str(item.get("kind") or "other")
                    links[kind] = str(item["uri"])

        ctx = json.loads(row["contexts"] or "[]")
        if not isinstance(ctx, list):
            ctx = []
        assignees = json.loads(row["assignees"] or "[]")
        if not isinstance(assignees, list):
            assignees = []

        return TaskRecord(
            id=str(row["id"]),
            title=str(row["title"]),
            section=str(row["section"]),
            due=row["due"],
            defer=row["defer"],
            done=row["done"],
            ctx=[str(item) for item in ctx],
            assignees=[str(item) for item in assignees],
            flagged=bool(row["flagged"]),
            links=links,
            notes=row["notes"],
        )

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

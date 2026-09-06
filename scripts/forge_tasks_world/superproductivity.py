"""Super Productivity REST integration for Forge.

When ``superproductivity.enabled`` is true, Super Productivity is the sole task
store (inbox, dues, capture). Forge remains the project kanban nexus. A legacy
three-way ``TASKS.toml`` sync remains available for mapped pilots; capture and
briefs prefer live SP. The adapter never deletes tasks or projects.
"""

from __future__ import annotations

import fcntl
import json
import os
import re
import subprocess
import urllib.error
import urllib.parse
import urllib.request
from contextlib import contextmanager
from dataclasses import dataclass, field
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any, Iterator

from .capture import extract_uri_from_notes, format_sp_note_attachment, new_task_id
from .toml_io import ProjectTasks, TaskRecord, load_project_tasks, project_tasks_path, write_project_tasks

BACKEND = "super-productivity"
DEFAULT_ENDPOINT = "http://127.0.0.1:3876"
TOKEN_SERVICE = "forge-superproductivity"
INBOX_PROJECT_ID = "INBOX_PROJECT"
FORGE_ID_MARKER_RE = re.compile(r"<!--\s*forge:id:([A-Za-z0-9_-]+)\s*-->")
FORGE_SOURCE_RE = re.compile(r"\[forge:source:([a-z0-9_-]+)\]", re.IGNORECASE)
SYNC_FIELDS = ("title", "section_open", "due", "planned", "estimate_minutes", "recorded_minutes", "notes")


class SuperProductivityError(RuntimeError):
    """A safe, user-facing Super Productivity integration failure."""


def _redact(value: str) -> str:
    """Remove credentials from an error message."""
    token = os.environ.get("FORGE_SP_TOKEN", "")
    redacted = value
    if token:
        redacted = redacted.replace(token, "[redacted]")
    return redacted


def keychain_token(*, prompt: bool = False) -> str | None:
    """Read the API token from Keychain (macOS), secret-tool, or a local token file."""
    env = os.environ.get("FORGE_SP_TOKEN", "").strip()
    if env:
        return env

    # macOS Keychain
    try:
        result = subprocess.run(
            ["security", "find-generic-password", "-s", TOKEN_SERVICE, "-w"],
            capture_output=True,
            text=True,
            check=False,
        )
        token = result.stdout.strip() if result.returncode == 0 else ""
    except OSError:
        token = ""
    if token:
        return token

    # Linux secret-tool
    try:
        result = subprocess.run(
            ["secret-tool", "lookup", "service", TOKEN_SERVICE],
            capture_output=True,
            text=True,
            check=False,
        )
        token = result.stdout.strip() if result.returncode == 0 else ""
    except OSError:
        token = ""
    if token:
        return token

    # Local file (Linux / CI): ~/.config/forge/superproductivity.token
    token_path = Path.home() / ".config" / "forge" / "superproductivity.token"
    if token_path.is_file():
        token = token_path.read_text(encoding="utf-8").strip()
        if token:
            return token

    if not prompt:
        return None
    import getpass

    token = getpass.getpass("Super Productivity API token (hidden): ").strip()
    if not token:
        return None

    # Prefer Keychain on macOS
    try:
        result = subprocess.run(
            ["security", "add-generic-password", "-U", "-s", TOKEN_SERVICE, "-a", "forge", "-w", token],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode == 0:
            return token
    except OSError:
        pass

    try:
        result = subprocess.run(
            ["secret-tool", "store", "--label", "Forge Super Productivity", "service", TOKEN_SERVICE],
            input=token,
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode == 0:
            return token
    except OSError:
        pass

    token_path.parent.mkdir(parents=True, exist_ok=True)
    token_path.write_text(token + "\n", encoding="utf-8")
    token_path.chmod(0o600)
    return token


def _yaml_mapping(text: str) -> dict[str, Any]:
    """Decode configuration with the shared safe YAML parser."""
    try:
        import yaml
    except ImportError as exc:
        raise ValueError("PyYAML required: install scripts/requirements.txt") from exc
    try:
        value = yaml.safe_load(text)
    except yaml.YAMLError as exc:
        raise ValueError("Invalid Forge YAML configuration") from exc
    if value is None:
        return {}
    if not isinstance(value, dict):
        raise ValueError("Forge configuration must be a mapping")
    return value


def board_column_tags_from_yaml(text: str) -> dict[str, str]:
    """Return configured column names and tags using the same YAML decoder as SP."""
    board = _yaml_mapping(text).get("board") or {}
    return {str(column["name"]): str(column["tag"])
            for column in board.get("columns", [])}


def nexus_sp_column_mirror_enabled(text: str) -> bool:
    """Return whether ``nexus.sp_column_mirror`` is enabled in config YAML."""
    nexus = _yaml_mapping(text).get("nexus") or {}
    value = nexus.get("sp_column_mirror", False)
    if not isinstance(value, bool):
        raise ValueError("nexus.sp_column_mirror must be a boolean")
    return value


def mirror_board_column_tags(
    client: "SuperProductivityClient",
    *,
    board_projects: list[dict[str, Any]],
    project_ids: dict[str, str],
    column_tags: dict[str, str],
) -> dict[str, Any]:
    """Mirror Finder column tags onto SP tasks for every mapped board project.

    Skips unmapped folders, projects with no column, and unknown column names.
    Reuses ``mirror_column_tags`` per project (one tag list fetch shared via
    repeated ``client.tags()`` calls — acceptable for morning reconcile size).
    """
    kanban_titles = list(column_tags.values())
    results: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []
    updated_tasks = 0
    failures = 0

    for project in board_projects:
        name = str(project.get("name") or "").strip()
        column = str(project.get("column") or "").strip()
        if not name:
            continue
        project_id = project_ids.get(name)
        if not project_id:
            skipped.append({"project": name, "reason": "unmapped"})
            continue
        if not column or column == "(none)":
            skipped.append({"project": name, "reason": "no_column"})
            continue
        tag_title = column_tags.get(column)
        if not tag_title:
            skipped.append({"project": name, "column": column, "reason": "unknown_column"})
            continue
        result = mirror_column_tags(
            client,
            project_id=project_id,
            column=column,
            tag_title=tag_title,
            kanban_tag_titles=kanban_titles,
        )
        entry = {
            "project": name,
            "column": column,
            "ok": bool(result.get("ok")),
            "tag": result.get("tag"),
            "updated": int(result.get("updated") or 0),
        }
        if result.get("error"):
            entry["error"] = result["error"]
            failures += 1
        else:
            updated_tasks += entry["updated"]
        results.append(entry)

    return {
        "ok": failures == 0,
        "mirrored": len(results),
        "updated_tasks": updated_tasks,
        "failures": failures,
        "skipped": skipped,
        "projects": results,
    }


def mirror_column_tags(
    client: "SuperProductivityClient",
    *,
    project_id: str,
    column: str,
    tag_title: str | None = None,
    kanban_tag_titles: list[str] | None = None,
) -> dict[str, Any]:
    """Replace kanban column tags on active tasks in an SP project.

    Prefers the Finder-identical tag string (e.g. ``Coding 🤖``). Falls back to
    ``Forge/<Column>``. Tags must already exist in Super Productivity.
    """
    desired_title = tag_title or f"Forge/{column}"
    tags = client.tags()
    by_title = {
        str(tag.get("title") or ""): str(tag.get("id") or "")
        for tag in (tags or [])
        if tag.get("id")
    }
    desired_id = by_title.get(desired_title)
    if not desired_id:
        return {
            "ok": False,
            "error": f"SP tag '{desired_title}' not found; create it in Super Productivity first",
            "updated": 0,
        }
    strip_titles = set(kanban_tag_titles or [])
    strip_titles.add(desired_title)
    strip_titles.update(title for title in by_title if title.startswith("Forge/"))
    # Also strip other known board-looking emoji tags already in SP that match kanban list
    strip_ids = {by_title[t] for t in strip_titles if t in by_title}
    tasks = client.tasks(project_id)
    updated = 0
    for task in tasks:
        tag_ids = list(task.get("tagIds") or [])
        cleaned = [tid for tid in tag_ids if tid not in strip_ids]
        if desired_id not in cleaned:
            cleaned.append(desired_id)
        if cleaned == tag_ids:
            continue
        client.update_task(str(task["id"]), {"tagIds": cleaned})
        updated += 1
    return {"ok": True, "tag": desired_title, "tag_id": desired_id, "updated": updated}


@dataclass(frozen=True)
class SuperProductivityConfig:
    """Runtime settings for the explicitly enabled integration."""

    enabled: bool = False
    endpoint: str = DEFAULT_ENDPOINT
    project_ids: dict[str, str] = field(default_factory=dict)
    timeout: float = 5.0
    #: When true with ``enabled``, SP is the day-to-day task store (OF frozen).
    primary: bool = False

    @classmethod
    def from_mapping(cls, value: dict[str, Any] | None) -> "SuperProductivityConfig":
        """Validate decoded Super Productivity settings."""
        value = {} if value is None else value
        if not isinstance(value, dict):
            raise ValueError("superproductivity must be a mapping")
        if not isinstance(value.get("enabled", False), bool):
            raise ValueError("superproductivity.enabled must be a boolean")
        if "primary" in value and not isinstance(value.get("primary"), bool):
            raise ValueError("superproductivity.primary must be a boolean")
        endpoint = str(value.get("endpoint", DEFAULT_ENDPOINT)).rstrip("/")
        if not _is_loopback_endpoint(endpoint):
            raise ValueError("Super Productivity endpoint must be loopback")
        project_ids = value.get("project_ids") or {}
        if not isinstance(project_ids, dict):
            raise ValueError("superproductivity.project_ids must be a mapping")
        return cls(
            enabled=bool(value.get("enabled", False)),
            endpoint=endpoint,
            project_ids={str(key): str(ident) for key, ident in project_ids.items()},
            timeout=float(value.get("timeout", 5.0)),
            primary=bool(value.get("primary", False)),
        )

    @property
    def mapped_projects(self) -> list[str]:
        """Return sorted mapped project folder names."""
        return sorted(self.project_ids)

    @property
    def is_primary_task_store(self) -> bool:
        """Return True when SP is enabled and marked primary for day-to-day tasks."""
        return self.enabled and self.primary


def refuse_of_import_while_primary(
    config: SuperProductivityConfig,
    *,
    allow: bool,
    action: str,
) -> None:
    """Exit if an OmniFocus→SP import is blocked by ``primary`` without override."""
    if config.is_primary_task_store and not allow:
        raise SystemExit(
            f"{action} blocked: superproductivity.primary is true "
            "(OmniFocus frozen / SP primary for dogfooding). "
            "Pass --allow-while-primary only for intentional one-shot imports. "
            "See docs/of-frozen-sp-primary.md."
        )


def _is_loopback_endpoint(endpoint: str) -> bool:
    """Return True when the endpoint is the supported local REST base URL."""
    return endpoint == DEFAULT_ENDPOINT or endpoint.startswith(DEFAULT_ENDPOINT + "/")


def config_from_yaml_text(text: str) -> SuperProductivityConfig:
    """Parse the Super Productivity settings using safe YAML decoding."""
    return SuperProductivityConfig.from_mapping(_yaml_mapping(text).get("superproductivity"))


def config_from_file(path: Path) -> SuperProductivityConfig:
    """Load Super Productivity settings from ``config.yaml``."""
    if not path.exists():
        return SuperProductivityConfig()
    return config_from_yaml_text(path.read_text(encoding="utf-8"))


class SuperProductivityClient:
    """Minimal authenticated client for the local SP REST API."""

    def __init__(self, config: SuperProductivityConfig, token: str | None = None):
        self.config = config
        self.token = token

    def request(
        self,
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
        *,
        authenticate: bool = True,
    ) -> Any:
        """Issue one local API request and return the unwrapped ``data`` payload."""
        if not _is_loopback_endpoint(self.config.endpoint):
            raise SuperProductivityError("refusing a non-loopback endpoint")
        url = self.config.endpoint + (path if path.startswith("/") else "/" + path)
        data = None if payload is None else json.dumps(payload).encode()
        request = urllib.request.Request(
            url,
            data=data,
            method=method.upper(),
            headers={"Accept": "application/json", "Content-Type": "application/json"},
        )
        if authenticate:
            if not self.token:
                raise SuperProductivityError("Super Productivity API token is not configured")
            request.add_header("Authorization", "Bearer " + self.token)
        opener = urllib.request.build_opener(NoRedirectHandler)
        try:
            with opener.open(request, timeout=self.config.timeout) as response:
                if response.geturl().rstrip("/") != url.rstrip("/"):
                    raise SuperProductivityError("refusing redirected Super Productivity response")
                raw = response.read().decode("utf-8")
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            raise SuperProductivityError(_redact(_http_error_message(exc.code, body))) from exc
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            raise SuperProductivityError(_redact(str(exc))) from exc
        if not raw:
            return None
        try:
            decoded = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise SuperProductivityError("Super Productivity returned malformed JSON") from exc
        return _unwrap_envelope(decoded)

    def health(self) -> Any:
        """Return the unauthenticated health probe."""
        return self.request("GET", "/health", authenticate=False)

    def projects(self) -> list[dict[str, Any]]:
        """Return projects from the API."""
        data = self.request("GET", "/projects")
        return _as_list(data, "projects")

    def tags(self) -> list[dict[str, Any]]:
        """Return tags from the API."""
        data = self.request("GET", "/tags")
        return _as_list(data, "tags")

    def tasks(self, project_id: str, *, include_done: bool = True) -> list[dict[str, Any]]:
        """Return tasks for one project."""
        query = urllib.parse.urlencode(
            {"projectId": project_id, "includeDone": "true" if include_done else "false"}
        )
        data = self.request("GET", f"/tasks?{query}")
        return _as_list(data, "tasks")

    def create_task(self, project_id: str, payload: dict[str, Any]) -> Any:
        """Create a task in a mapped project."""
        body = dict(payload)
        body["projectId"] = project_id
        return self.request("POST", "/tasks", body)

    def update_task(self, task_id: str, payload: dict[str, Any]) -> Any:
        """Update a task using PATCH."""
        return self.request("PATCH", f"/tasks/{task_id}", payload)

    def start_task(self, task_id: str) -> Any:
        """Start one task."""
        return self.request("POST", f"/tasks/{task_id}/start")

    def stop_task(self) -> Any:
        """Stop the currently running task."""
        return self.request("POST", "/task-control/stop")

    def focus(self) -> Any:
        """Read the current focus state."""
        return self.request("GET", "/focus")

    def delete_task(self, task_id: str) -> Any:
        """Delete a task only when an explicit caller requests it."""
        return self.request("DELETE", f"/tasks/{task_id}")


def open_client(forge_home: Path, *, prompt_token: bool = False) -> SuperProductivityClient:
    """Build an authenticated client from Forge home ``config.yaml``."""
    config = config_from_file(forge_home / "config.yaml")
    if not config.enabled:
        raise SuperProductivityError("superproductivity.enabled is false")
    token = keychain_token(prompt=prompt_token)
    if not token:
        raise SuperProductivityError(
            "Super Productivity API token missing; run forge superproductivity setup-token"
        )
    return SuperProductivityClient(config, token)


def _created_task_id(created: Any) -> str:
    """Extract the SP task id from a create response."""
    if isinstance(created, dict):
        for key in ("id", "taskId"):
            value = created.get(key)
            if value:
                return str(value)
        task = created.get("task")
        if isinstance(task, dict) and task.get("id"):
            return str(task["id"])
    if isinstance(created, str) and created.strip():
        return created.strip()
    raise SuperProductivityError("Super Productivity create-task response lacked an id")


def _task_due_day(task: dict[str, Any]) -> str | None:
    """Return YYYY-MM-DD due day from an SP task, if any."""
    due_day = task.get("dueDay")
    if isinstance(due_day, str) and due_day.strip():
        return due_day.strip()[:10]
    due_with_time = task.get("dueWithTime")
    if due_with_time is None:
        return None
    try:
        millis = int(due_with_time)
    except (TypeError, ValueError):
        return None
    return datetime.fromtimestamp(millis / 1000.0, tz=timezone.utc).date().isoformat()


def _parse_source_from_notes(notes: str | None) -> str | None:
    """Read an optional ``[forge:source:…]`` marker from SP notes."""
    if not notes:
        return None
    match = FORGE_SOURCE_RE.search(notes)
    return match.group(1).lower() if match else None


def _first_uri_from_notes(notes: str | None) -> str | None:
    """Return the first http(s)/file/message URI found in notes.

    Accepts bare URI lines, ``<uri>`` autolinks, and markdown ``[label](uri)``
    (the form Forge writes for Super Productivity).
    """
    return extract_uri_from_notes(notes)

@dataclass(frozen=True)
class SpInboxItem:
    """One open Super Productivity Inbox task."""

    task_id: str
    title: str
    source: str | None
    created_at: str | None
    notes: str | None
    links: list[dict[str, str]]


@dataclass(frozen=True)
class SpDueItem:
    """One open Super Productivity task with a due date."""

    task_id: str
    title: str
    project_name: str
    project_id: str
    due: str
    section: str


class SpTaskStore:
    """Capture / inbox / assign / complete / due against live Super Productivity."""

    def __init__(self, forge_home: Path, client: SuperProductivityClient | None = None) -> None:
        """Initialise against Forge home; optionally inject a client (tests)."""
        self.forge_home = forge_home
        self.client = client or open_client(forge_home)
        self.inbox_dir = forge_home / ".forge" / "inbox"

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
    ) -> SpInboxItem:
        """Create an Inbox task in Super Productivity."""
        clean_title = title.strip()
        if not clean_title:
            raise ValueError("capture title must not be empty")

        source_key = (source or "cli").strip().lower() or "cli"
        note_parts: list[str] = [f"[forge:source:{source_key}]"]
        if note and note.strip():
            note_parts.append(note.strip())

        uri = (link or "").strip() or None
        resolved_file: Path | None = None
        if file_path is not None:
            resolved_file = file_path.expanduser().resolve()
            if not resolved_file.exists():
                raise FileNotFoundError(f"file not found: {resolved_file}")
            uri = resolved_file.as_uri()
            kind = "file"

        link_lines: list[str] = []
        if uri:
            link_lines = format_sp_note_attachment(
                uri, kind=kind, forge_home=self.forge_home
            )
            note_parts.extend(link_lines)

        payload: dict[str, Any] = {"title": clean_title, "notes": "\n".join(note_parts)}
        created = self.client.create_task(INBOX_PROJECT_ID, payload)
        task_id = _created_task_id(created)

        links: list[dict[str, str]] = []
        if uri:
            links.append({"kind": (kind or "link"), "uri": uri})

        if stash and resolved_file is not None and link_lines:
            stashed = self._stash_file(task_id, resolved_file)
            stashed_uri = stashed.as_uri()
            stashed_lines = format_sp_note_attachment(
                stashed_uri, kind="file", forge_home=self.forge_home
            )
            # Drop previous attachment lines, then append stashed ones.
            kept = note_parts[: -len(link_lines)] if link_lines else list(note_parts)
            note_parts = [*kept, *stashed_lines]
            payload_notes = "\n".join(note_parts)
            self.client.update_task(task_id, {"notes": payload_notes})
            links = [{"kind": "file", "uri": stashed_uri}]
            note_parts = [payload_notes]
        return SpInboxItem(
            task_id=task_id,
            title=clean_title,
            source=source_key,
            created_at=None,
            notes="\n".join(note_parts),
            links=links,
        )

    def list_inbox(self) -> list[SpInboxItem]:
        """Return open Inbox tasks from Super Productivity."""
        items: list[SpInboxItem] = []
        for task in self.client.tasks(INBOX_PROJECT_ID, include_done=False):
            if task.get("isDone"):
                continue
            notes = task.get("notes")
            notes_s = str(notes) if notes else None
            uri = _first_uri_from_notes(notes_s)
            links = [{"kind": "link", "uri": uri}] if uri else []
            created = task.get("created") or task.get("createdAt")
            created_s = None
            if isinstance(created, (int, float)):
                created_s = datetime.fromtimestamp(created / 1000.0, tz=timezone.utc).isoformat()
            elif isinstance(created, str):
                created_s = created
            items.append(
                SpInboxItem(
                    task_id=str(task.get("id") or ""),
                    title=str(task.get("title") or ""),
                    source=_parse_source_from_notes(notes_s),
                    created_at=created_s,
                    notes=notes_s,
                    links=links,
                )
            )
        return [item for item in items if item.task_id]

    def assign(self, task_id: str, project_name: str) -> None:
        """Move an Inbox (or any) task onto a mapped Super Productivity project."""
        project_id = self.client.config.project_ids.get(project_name)
        if not project_id:
            raise KeyError(
                f"No Super Productivity project_ids entry for '{project_name}'. "
                "Create the SP project with that exact title and map it in config.yaml."
            )
        self.client.update_task(task_id, {"projectId": project_id})

    def complete(self, task_id: str) -> None:
        """Mark a Super Productivity task done."""
        self.client.update_task(task_id, {"isDone": True})

    def get_open_link(self, task_id: str) -> str | None:
        """Return the first URI embedded in the task notes, if any."""
        task = self.client.request("GET", f"/tasks/{task_id}")
        if not isinstance(task, dict):
            return None
        return _first_uri_from_notes(str(task.get("notes") or "") or None)

    def due_tasks(
        self,
        *,
        horizon_days: int,
        include_overdue: bool = True,
    ) -> tuple[list[SpDueItem], dict[str, Any]]:
        """Return open due tasks across all SP projects within the horizon."""
        today = date.today()
        horizon = today.toordinal() + max(0, horizon_days)
        projects = self.client.projects()
        title_by_id = {
            str(project.get("id")): str(project.get("title") or "")
            for project in projects
            if project.get("id")
        }
        # Inbox is a built-in project and may be absent from GET /projects.
        title_by_id.setdefault(INBOX_PROJECT_ID, "Inbox")
        rows: list[SpDueItem] = []
        open_count = 0
        for project_id, project_name in title_by_id.items():
            for task in self.client.tasks(project_id, include_done=False):
                if task.get("isDone"):
                    continue
                open_count += 1
                due = _task_due_day(task)
                if not due:
                    continue
                try:
                    due_day = date.fromisoformat(due)
                except ValueError:
                    continue
                if due_day.toordinal() > horizon:
                    continue
                if due_day < today and not include_overdue:
                    continue
                rows.append(
                    SpDueItem(
                        task_id=str(task.get("id") or ""),
                        title=str(task.get("title") or ""),
                        project_name=project_name or project_id,
                        project_id=project_id,
                        due=due,
                        section="next",
                    )
                )
        rows.sort(key=lambda row: (row.due, row.project_name, row.title))
        status = {
            "projects": len(title_by_id),
            "open_tasks": open_count,
            "db_path": self.client.config.endpoint,
            "backend": BACKEND,
        }
        return rows, status

    def _stash_file(self, task_id: str, source: Path) -> Path:
        """Copy a file into ``.forge/inbox/<id>/`` for durable local capture."""
        target_dir = self.inbox_dir / task_id
        target_dir.mkdir(parents=True, exist_ok=True)
        target = target_dir / source.name
        target.write_bytes(source.read_bytes())
        return target


class NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Reject redirects so tokens are never sent to an unexpected host."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: N802
        return None


def _unwrap_envelope(decoded: Any) -> Any:
    """Accept either a bare payload or the official ``{ok, data}`` envelope."""
    if isinstance(decoded, dict) and "ok" in decoded:
        if not decoded.get("ok"):
            error = decoded.get("error") or {}
            message = error.get("message") if isinstance(error, dict) else str(error)
            raise SuperProductivityError(_redact(message or "Super Productivity request failed"))
        return decoded.get("data")
    return decoded


def _as_list(data: Any, key: str) -> list[dict[str, Any]]:
    """Normalise list-or-envelope list payloads."""
    if isinstance(data, dict):
        data = data.get(key, data.get("data", []))
    return [item for item in (data or []) if isinstance(item, dict)]


def _http_error_message(code: int, body: str) -> str:
    """Build a redacted HTTP error message."""
    try:
        decoded = json.loads(body)
        if isinstance(decoded, dict):
            error = decoded.get("error") or {}
            if isinstance(error, dict) and error.get("message"):
                return f"HTTP {code}: {error['message']}"
    except json.JSONDecodeError:
        pass
    return f"HTTP {code}"


def forge_id_marker(task_id: str) -> str:
    """Return the managed Forge identity marker stored in SP notes."""
    return f"<!-- forge:id:{task_id} -->"


def split_notes(notes: str | None) -> tuple[str | None, str | None]:
    """Split user notes from the managed Forge identity marker."""
    if not notes:
        return None, None
    match = FORGE_ID_MARKER_RE.search(notes)
    forge_id = match.group(1) if match else None
    cleaned = FORGE_ID_MARKER_RE.sub("", notes).strip()
    return cleaned or None, forge_id


def combine_notes(user_notes: str | None, task_id: str) -> str:
    """Attach the managed Forge identity marker to user notes."""
    marker = forge_id_marker(task_id)
    if user_notes:
        return f"{user_notes.rstrip()}\n\n{marker}"
    return marker


def _minutes_from_ms(value: Any) -> int | None:
    """Convert SP millisecond durations to whole minutes."""
    if value is None or value == "":
        return None
    number = int(value)
    if number < 0:
        raise SuperProductivityError("Super Productivity duration cannot be negative")
    if number == 0:
        return None
    return max(1, int(round(number / 60_000)))


def _ms_from_minutes(value: int | None) -> int | None:
    """Convert whole minutes to SP millisecond durations."""
    if value is None:
        return None
    return int(value) * 60_000


def _format_planned(value: Any) -> str | None:
    """Format an SP planned timestamp or ISO string for TASKS.toml."""
    if value is None or value == "":
        return None
    if isinstance(value, (int, float)):
        instant = datetime.fromtimestamp(float(value) / 1000.0, tz=timezone.utc)
        return instant.astimezone().replace(microsecond=0).isoformat()
    text = str(value).strip()
    return text or None


def _planned_to_ms(value: str | None) -> int | None:
    """Convert a local planned date/time to an SP millisecond timestamp."""
    if not value:
        return None
    text = value.strip()
    try:
        if len(text) == 10 and text[4] == "-" and text[7] == "-":
            local = datetime.fromisoformat(text).astimezone().replace(
                hour=9, minute=0, second=0, microsecond=0
            )
        else:
            local = datetime.fromisoformat(text)
            if local.tzinfo is None:
                local = local.astimezone().replace(tzinfo=datetime.now().astimezone().tzinfo)
        return int(local.timestamp() * 1000)
    except ValueError as exc:
        raise SuperProductivityError(f"invalid planned date: {value}") from exc


def _due_from_remote(item: dict[str, Any]) -> str | None:
    """Prefer date-only deadlines; preserve timed deadlines as instants."""
    due_day = item.get("dueDay")
    if due_day:
        return str(due_day)[:10]
    due_with_time = item.get("dueWithTime")
    if due_with_time is None or due_with_time == "":
        return None
    if isinstance(due_with_time, (int, float)):
        instant = datetime.fromtimestamp(float(due_with_time) / 1000.0, tz=timezone.utc)
        return instant.astimezone().replace(microsecond=0).isoformat()
    return str(due_with_time)


def _due_payload(due: str | None) -> dict[str, Any]:
    """Build SP due fields from a TASKS.toml due value."""
    if not due:
        return {"dueDay": None, "dueWithTime": None}
    text = due.strip()
    if len(text) == 10 and text[4] == "-" and text[7] == "-":
        return {"dueDay": text, "dueWithTime": None}
    try:
        local = datetime.fromisoformat(text)
        if local.tzinfo is None:
            local = local.astimezone().replace(tzinfo=datetime.now().astimezone().tzinfo)
        return {"dueDay": None, "dueWithTime": int(local.timestamp() * 1000)}
    except ValueError as exc:
        raise SuperProductivityError(f"invalid due date: {due}") from exc


def task_from_remote(item: dict[str, Any], *, forge_id: str | None = None) -> TaskRecord:
    """Convert an SP task response to a Forge task record."""
    task_id = str(item.get("id") or item.get("_id") or "")
    if not task_id:
        raise SuperProductivityError("Super Productivity returned a task without an id")
    user_notes, marker_id = split_notes(item.get("notes") or item.get("note"))
    assigned_id = forge_id or marker_id or ("sp:" + task_id)
    done = bool(item.get("isDone", item.get("done", item.get("completed", False))))
    return TaskRecord(
        id=assigned_id,
        title=str(item.get("title") or item.get("name") or "").strip(),
        section="done" if done else "next",
        due=_due_from_remote(item),
        planned=_format_planned(item.get("plannedAt") or item.get("planned")),
        notes=user_notes,
        external_id=task_id,
        external_backend=BACKEND,
        estimate_minutes=_minutes_from_ms(item.get("timeEstimate")),
        recorded_minutes=_minutes_from_ms(item.get("timeSpent")),
    )


def sync_snapshot(task: TaskRecord) -> dict[str, Any]:
    """Return the comparable synchronisation state for one task."""
    notes, _ = split_notes(task.notes)
    return {
        "title": task.title,
        "section_open": task.section != "done",
        "due": task.due,
        "planned": task.planned,
        "estimate_minutes": task.estimate_minutes,
        "recorded_minutes": task.recorded_minutes,
        "notes": notes,
    }


def merge_snapshots(
    local: dict[str, Any],
    remote: dict[str, Any],
    baseline: dict[str, Any] | None,
) -> tuple[dict[str, Any], list[str], list[str], list[str]]:
    """Three-way merge comparable fields.

    Returns the merged snapshot plus push/pull/conflict field lists. Conflicting
    fields keep the local value and are not pushed.
    """
    baseline = baseline or {}
    merged = dict(local)
    push: list[str] = []
    pull: list[str] = []
    conflicts: list[str] = []
    for key in SYNC_FIELDS:
        local_value = local.get(key)
        remote_value = remote.get(key)
        base_value = baseline.get(key)
        if local_value == remote_value:
            merged[key] = local_value
            continue
        if key not in baseline or local_value == base_value:
            merged[key] = remote_value
            pull.append(key)
            continue
        if remote_value == base_value:
            merged[key] = local_value
            push.append(key)
            continue
        merged[key] = local_value
        conflicts.append(key)
    return merged, push, pull, conflicts


def apply_snapshot(task: TaskRecord, snapshot: dict[str, Any]) -> TaskRecord:
    """Apply a merged snapshot onto a task record."""
    if snapshot.get("section_open", True):
        if task.section == "done":
            section = "next"
        elif task.section in ("waiting", "someday", "next"):
            section = task.section
        else:
            section = "next"
    else:
        section = "done"
    return TaskRecord(
        id=task.id,
        title=str(snapshot.get("title") or task.title),
        section=section,
        due=snapshot.get("due"),
        defer=task.defer,
        planned=snapshot.get("planned"),
        done=task.done,
        ctx=list(task.ctx),
        assignees=list(task.assignees),
        flagged=task.flagged,
        links=dict(task.links),
        notes=snapshot.get("notes"),
        external_id=task.external_id,
        external_backend=task.external_backend or BACKEND,
        estimate_minutes=snapshot.get("estimate_minutes"),
        recorded_minutes=snapshot.get("recorded_minutes"),
    )


def remote_payload_from_snapshot(snapshot: dict[str, Any], *, task_id: str) -> dict[str, Any]:
    """Build an SP create/update body from a comparable snapshot.

    Omitted fields are left unchanged on update; ``null`` is rejected by the
    local REST validator for several create fields, so absent values are dropped.
    """
    payload: dict[str, Any] = {
        "title": snapshot["title"],
        "isDone": not snapshot.get("section_open", True),
        "notes": combine_notes(snapshot.get("notes"), task_id),
    }
    estimate = _ms_from_minutes(snapshot.get("estimate_minutes"))
    if estimate is not None:
        payload["timeEstimate"] = estimate
    recorded = _ms_from_minutes(snapshot.get("recorded_minutes"))
    if recorded is not None:
        payload["timeSpent"] = recorded
    planned = _planned_to_ms(snapshot.get("planned"))
    if planned is not None:
        payload["plannedAt"] = planned
    due = snapshot.get("due")
    if due:
        payload.update({key: value for key, value in _due_payload(due).items() if value is not None})
    return payload


def clear_due_payload() -> dict[str, Any]:
    """Return PATCH fields that clear both due representations."""
    return {"dueDay": None, "dueWithTime": None}


def defer_blocks_export(task: TaskRecord, *, today: date | None = None) -> bool:
    """Return True when a local defer date should keep the task out of SP."""
    if not task.defer:
        return False
    today = today or date.today()
    text = task.defer.strip()[:10]
    try:
        return date.fromisoformat(text) > today
    except ValueError:
        return False


def unsupported_export_reason(task: TaskRecord) -> str | None:
    """Return a reason when a local task must not be exported yet."""
    if task.external_id:
        return None
    if task.section in ("waiting", "someday"):
        return f"unsupported section '{task.section}'"
    if task.section == "done":
        return "completed local history is retained locally"
    if defer_blocks_export(task):
        return f"deferred until {task.defer}"
    return None


def ledger_path(forge_home: Path) -> Path:
    """Return the local, non-secret sync ledger path."""
    return forge_home / ".forge" / "superproductivity.json"


def lock_path(forge_home: Path) -> Path:
    """Return the process lock path for synchronisation."""
    return forge_home / ".forge" / "superproductivity.lock"


def load_ledger(forge_home: Path) -> dict[str, Any]:
    """Load the sync ledger, returning an empty structure when absent."""
    path = ledger_path(forge_home)
    if not path.exists():
        return {"version": 1, "updated_at": None, "projects": {}, "tasks": {}, "pending_creates": {}}
    data = json.loads(path.read_text(encoding="utf-8"))
    data.setdefault("version", 1)
    data.setdefault("projects", {})
    data.setdefault("tasks", {})
    data.setdefault("pending_creates", {})
    return data


def save_ledger(forge_home: Path, ledger: dict[str, Any]) -> None:
    """Atomically write the sync ledger without credentials."""
    path = ledger_path(forge_home)
    path.parent.mkdir(parents=True, exist_ok=True)
    ledger["updated_at"] = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(ledger, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(path)


@contextmanager
def sync_lock(forge_home: Path) -> Iterator[None]:
    """Hold an exclusive process lock for synchronisation."""
    path = lock_path(forge_home)
    path.parent.mkdir(parents=True, exist_ok=True)
    handle = path.open("a+", encoding="utf-8")
    try:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as exc:
        handle.close()
        raise SuperProductivityError("another Super Productivity sync is already running") from exc
    try:
        handle.seek(0)
        handle.truncate()
        handle.write(str(os.getpid()))
        handle.flush()
        yield
    finally:
        fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
        handle.close()


def backup_tasks_file(path: Path) -> Path | None:
    """Copy TASKS.toml beside itself before an apply write."""
    if not path.exists():
        return None
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    backup = path.with_name(f"TASKS.toml.pre-sp-{stamp}")
    backup.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
    return backup


def sync_project(
    *,
    client: SuperProductivityClient,
    project_id: str,
    project_name: str,
    project_dir: Path,
    ledger: dict[str, Any],
    apply: bool = False,
) -> dict[str, Any]:
    """Preview or apply a three-way sync for one mapped project."""
    path = project_tasks_path(project_dir)
    local = load_project_tasks(path) if path.exists() else ProjectTasks(project=project_name)
    remote_items = client.tasks(project_id)
    remote_by_id = {str(item.get("id") or item.get("_id")): item for item in remote_items}
    remote_by_marker: dict[str, dict[str, Any]] = {}
    for item in remote_items:
        _, marker = split_notes(item.get("notes") or item.get("note"))
        if marker:
            remote_by_marker[marker] = item

    changes: list[dict[str, Any]] = []
    conflicts: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []
    missing_remote: list[dict[str, Any]] = []
    working = {task.id: task for task in local.tasks}
    baselines = ledger.setdefault("tasks", {})
    pending = ledger.setdefault("pending_creates", {})
    mutated = False

    # Reconcile timed-out pending creates before exporting again.
    for forge_id, pending_info in list(pending.items()):
        if pending_info.get("project") != project_name:
            continue
        matched = remote_by_marker.get(forge_id)
        if matched is None:
            continue
        task = working.get(forge_id)
        if task is None:
            continue
        remote_task = task_from_remote(matched, forge_id=forge_id)
        remote_task = TaskRecord(**{**remote_task.__dict__, "defer": task.defer, "ctx": task.ctx,
                                    "assignees": task.assignees, "flagged": task.flagged,
                                    "links": task.links})
        working[forge_id] = remote_task
        baselines[forge_id] = {
            "external_id": remote_task.external_id,
            "snapshot": sync_snapshot(remote_task),
        }
        pending.pop(forge_id, None)
        mutated = True
        changes.append({"id": forge_id, "title": task.title, "action": "reconcile-create"})

    matched_remote_ids: set[str] = set()

    for task in list(working.values()):
        if task.external_backend and task.external_backend != BACKEND:
            continue
        baseline_entry = baselines.get(task.id) or {}
        baseline = baseline_entry.get("snapshot")
        remote_item = None
        if task.external_id and task.external_id in remote_by_id:
            remote_item = remote_by_id[task.external_id]
        elif task.id in remote_by_marker:
            remote_item = remote_by_marker[task.id]

        if remote_item is None and task.external_id:
            missing_remote.append({"id": task.id, "title": task.title, "external_id": task.external_id})
            continue

        if remote_item is None:
            reason = unsupported_export_reason(task)
            if reason:
                skipped.append({"id": task.id, "title": task.title, "reason": reason})
                continue
            snapshot = sync_snapshot(task)
            changes.append({"id": task.id, "title": task.title, "action": "create-remote", "fields": list(SYNC_FIELDS)})
            if apply:
                pending[task.id] = {"project": project_name, "snapshot": snapshot}
                created = client.create_task(project_id, remote_payload_from_snapshot(snapshot, task_id=task.id))
                created_item = created if isinstance(created, dict) else {"id": created}
                remote_task = task_from_remote(created_item, forge_id=task.id)
                updated = apply_snapshot(task, sync_snapshot(remote_task))
                updated = TaskRecord(**{**updated.__dict__, "external_id": remote_task.external_id,
                                        "external_backend": BACKEND, "defer": task.defer})
                working[task.id] = updated
                baselines[task.id] = {"external_id": updated.external_id, "snapshot": sync_snapshot(updated)}
                pending.pop(task.id, None)
                mutated = True
                if updated.external_id:
                    matched_remote_ids.add(updated.external_id)
            continue

        remote_id = str(remote_item.get("id") or remote_item.get("_id"))
        matched_remote_ids.add(remote_id)
        remote_task = task_from_remote(remote_item, forge_id=task.id)
        local_linked = task
        if not local_linked.external_id:
            local_linked = TaskRecord(**{**task.__dict__, "external_id": remote_id, "external_backend": BACKEND})
        merged, push, pull, conflict_fields = merge_snapshots(
            sync_snapshot(local_linked),
            sync_snapshot(remote_task),
            baseline,
        )
        if conflict_fields:
            conflicts.append({"id": task.id, "title": task.title, "fields": conflict_fields})
        if not push and not pull and not conflict_fields and local_linked.external_id:
            continue
        if push or pull:
            changes.append({
                "id": task.id,
                "title": task.title,
                "action": "merge",
                "push": push,
                "pull": pull,
            })
        if apply and (push or pull or not task.external_id):
            updated = apply_snapshot(local_linked, merged)
            updated = TaskRecord(**{**updated.__dict__, "external_id": remote_id, "external_backend": BACKEND,
                                    "defer": task.defer})
            if push:
                client.update_task(remote_id, remote_payload_from_snapshot(merged, task_id=task.id))
            working[task.id] = updated
            baselines[task.id] = {"external_id": remote_id, "snapshot": sync_snapshot(updated)}
            mutated = True

    for remote_id, item in remote_by_id.items():
        if remote_id in matched_remote_ids:
            continue
        _, marker = split_notes(item.get("notes") or item.get("note"))
        if marker and marker in working:
            continue
        remote_task = task_from_remote(item, forge_id=marker or new_task_id())
        changes.append({"id": remote_task.id, "title": remote_task.title, "action": "import-remote"})
        if apply:
            working[remote_task.id] = remote_task
            baselines[remote_task.id] = {
                "external_id": remote_id,
                "snapshot": sync_snapshot(remote_task),
            }
            mutated = True

    result = {
        "project": project_name,
        "remote_tasks": len(remote_items),
        "changes": changes,
        "conflicts": conflicts,
        "skipped": skipped,
        "missing_remote": missing_remote,
        "applied": False,
    }
    if apply and mutated:
        backup_tasks_file(path)
        write_project_tasks(
            ProjectTasks(project=project_name, notes_body=local.notes_body, tasks=list(working.values()), path=path),
            path,
        )
        result["applied"] = True
    return result


def refresh_project(
    *,
    client: SuperProductivityClient,
    project_id: str,
    project_name: str,
    project_dir: Path,
    apply: bool = False,
) -> dict[str, Any]:
    """Preview or apply a conservative SP-to-TASKS import for one project."""
    path = project_tasks_path(project_dir)
    local = load_project_tasks(path) if path.exists() else ProjectTasks(project=project_name)
    remote = client.tasks(project_id)
    converted = [task_from_remote(item) for item in remote]
    by_external = {
        task.external_id: task
        for task in local.tasks
        if task.external_backend == BACKEND and task.external_id
    }
    by_marker = {}
    for task in local.tasks:
        if task.external_backend == BACKEND:
            by_marker[task.id] = task
    changes = []
    updated_tasks = list(local.tasks)
    for task in converted:
        old = by_external.get(task.external_id) or by_marker.get(task.id)
        if old is not None:
            task = TaskRecord(**{**task.__dict__, "id": old.id, "defer": old.defer, "ctx": old.ctx,
                                 "assignees": old.assignees, "flagged": old.flagged, "links": old.links})
        if old is None or sync_snapshot(old) != sync_snapshot(task):
            changes.append({"id": task.id, "title": task.title, "action": "add" if old is None else "update"})
            if apply:
                updated_tasks = [
                    item
                    for item in updated_tasks
                    if not (item.external_id == task.external_id and item.external_backend == BACKEND)
                ]
                updated_tasks.append(task)
    if apply and changes:
        backup_tasks_file(path)
        write_project_tasks(
            ProjectTasks(project=project_name, notes_body=local.notes_body, tasks=updated_tasks, path=path),
            path,
        )
    return {
        "project": project_name,
        "remote_tasks": len(remote),
        "changes": changes,
        "applied": bool(apply and changes),
    }

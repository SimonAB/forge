"""OmniFocus → Super Productivity destination titles.

Policy (Hephaestus / SP primary):

1. Per-task OmniFocus ``forgeFolder`` when set (action-level Forge link), using
   board spelling when that folder is on the kanban, otherwise the forgeFolder
   string when an SP project with that title exists.
2. Else the OmniFocus **project** map: Finder / board spelling when the OF
   project maps to a board folder; otherwise the OF project title (or alias
   such as Rivka Lim - PDRA).

Empty OmniFocus projects are omitted from the project-level map.
"""

from __future__ import annotations

from collections import Counter, defaultdict
from typing import Any

from .of_mapping import (
    canonical_board_name,
    fold_title,
    keep_task,
    lookup_alias,
)


def preferred_forge_folder(
    of_project: str,
    *,
    project_forge: dict[str, str | None],
    forge_paths: dict[str, Any],
) -> str | None:
    """Best Forge folder for an OmniFocus project (alias, OF link, or board name)."""
    alias = lookup_alias(of_project)
    if alias:
        return canonical_board_name(alias, forge_paths) or alias
    linked = project_forge.get(of_project)
    if linked:
        return canonical_board_name(linked, forge_paths) or linked
    return canonical_board_name(of_project, forge_paths)


def pending_counts_by_of_project(of_data: dict[str, Any]) -> Counter[str]:
    """Count pending OmniFocus tasks per containing project name."""
    projects = of_data.get("projects") or []
    of_project_ids = {project["id"] for project in projects}
    counts: Counter[str] = Counter()
    for task in of_data.get("tasks") or []:
        if task.get("completed") or task.get("dropped"):
            continue
        if not keep_task(task, of_project_ids):
            continue
        name = (task.get("ofProjectName") or "").strip()
        if not name:
            continue
        counts[name] += 1
    return counts


def build_sp_destination_map(
    of_data: dict[str, Any],
    *,
    forge_paths: dict[str, Any],
) -> dict[str, str]:
    """Map OmniFocus project name → Super Productivity project title.

    Only non-empty OmniFocus projects are included. Board-folder destinations
    use Finder spelling; collision and unmapped cases use the OF title.
    """
    project_forge = {
        project["name"]: project.get("forgeFolder") for project in of_data.get("projects") or []
    }
    pending = pending_counts_by_of_project(of_data)
    nonempty = [
        name
        for name, count in pending.items()
        if count > 0 and not name.startswith("__probe_")
    ]

    board_members: dict[str, list[str]] = defaultdict(list)
    off_board_alias: dict[str, str] = {}
    no_board: list[str] = []
    for of_name in nonempty:
        preferred = preferred_forge_folder(
            of_name, project_forge=project_forge, forge_paths=forge_paths
        )
        board = canonical_board_name(preferred, forge_paths) if preferred else None
        if board:
            board_members[board].append(of_name)
        elif preferred:
            # Alias / linked name that is not a current board folder (e.g. Rivka Lim - PDRA).
            off_board_alias[of_name] = preferred
        else:
            no_board.append(of_name)

    destinations: dict[str, str] = {}
    for board, members in board_members.items():
        # Prefer Finder spelling for every OF project that maps to this folder
        # (including former shared buckets such as PGT / ZebraFinches).
        for of_name in members:
            destinations[of_name] = board
    for of_name, preferred in off_board_alias.items():
        destinations[of_name] = preferred
    for of_name in no_board:
        destinations[of_name] = of_name
    return destinations


def lookup_sp_project_id(
    title: str,
    *,
    project_ids: dict[str, str],
    sp_by_title: dict[str, str],
) -> str | None:
    """Resolve an SP project id by exact or folded title.

    ``project_ids`` entries are used only when that id still exists among
    live Super Productivity projects (values of ``sp_by_title``).
    """
    live_ids = set(sp_by_title.values())

    def _accept(ident: str | None) -> str | None:
        if ident and ident in live_ids:
            return ident
        return None

    if title in project_ids:
        found = _accept(project_ids[title])
        if found:
            return found
    if title in sp_by_title:
        return sp_by_title[title]
    want = fold_title(title)
    for key, ident in project_ids.items():
        if fold_title(key) == want:
            found = _accept(ident)
            if found:
                return found
    for key, ident in sp_by_title.items():
        if fold_title(key) == want:
            return ident
    return None


def destination_for_task(
    task: dict[str, Any],
    *,
    dest_by_of_project: dict[str, str],
    forge_paths: dict[str, Any],
    sp_by_title: dict[str, str] | None = None,
) -> str:
    """Return the SP project title for one OmniFocus task.

    Prefers the task's ``forgeFolder`` (when it matches a board folder or an
    existing SP title). Otherwise uses the OF-project destination map.
    """
    sp_by_title = sp_by_title or {}
    forge_folder = (task.get("forgeFolder") or "").strip() or None
    if forge_folder:
        board = canonical_board_name(forge_folder, forge_paths)
        if board:
            return board
        if lookup_sp_project_id(forge_folder, project_ids={}, sp_by_title=sp_by_title):
            want = fold_title(forge_folder)
            for title in sp_by_title:
                if fold_title(title) == want:
                    return title
            return forge_folder
        # Archived / unknown forgeFolder: fall through to OF project map.

    of_project = (task.get("ofProjectName") or "").strip() or None
    if not of_project:
        return "Inbox"
    preferred = dest_by_of_project.get(of_project) or of_project
    if lookup_sp_project_id(preferred, project_ids={}, sp_by_title=sp_by_title):
        want = fold_title(preferred)
        for title in sp_by_title:
            if fold_title(title) == want:
                return title
        return preferred
    # Preferred Finder title not in SP yet — keep tasks in an existing OF-titled project.
    if lookup_sp_project_id(of_project, project_ids={}, sp_by_title=sp_by_title):
        want = fold_title(of_project)
        for title in sp_by_title:
            if fold_title(title) == want:
                return title
        return of_project
    return preferred

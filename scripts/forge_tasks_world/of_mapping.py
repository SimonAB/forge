"""Map OmniFocus projects and tasks onto Forge project folders."""

from __future__ import annotations

import unicodedata

PROJECT_FOLDER_ALIASES: dict[str, str | None] = {
    "SLiMs model paper": "SLiMs_manuscript",
    "Oncho MIRS-AI Gates project": "Oncho-MIRS-AI_Gates",
    "Causal Dynamics of Complex Systems (CDCS)": "causal-dynamics-concept-notes",
    "Viral Host Predictor v2": "Viruses-ViralHostPredictor",
    # VectorPredictor keeps its own SP/OF title (paper/site work ≠ VHP code folder).
    "Activate grant [Wellcome, Leverhulme, ERC] Application": "Apodemus - Wild Vaccines WT discovery",
    "Birds_light_at_night NERC": "ZebraFinches",
    "Zebrafinches transcriptomes NERC": "ZebraFinches",
    "Sunfish - NERC EOI": "ZebraFinches",
    "Lepto Leverhulme app": "Lepto",
    "Wild Vaccines: submit Leverhulme proposal ": "Apodemus - Wild Vaccines WT discovery",
    "Wild Vaccines: submit Leverhulme proposal": "Apodemus - Wild Vaccines WT discovery",
    "Apodemus - Wild Vaccines BIG GRANT - WT discovery, ERC": "Apodemus - Wild Vaccines WT discovery",
    "Apodemus-DTV_Vaccines": "Apodemus - Wild Vaccines WT discovery",
    "Mozzies - Open Philanthropy": "Mozzies Open Philanthropy",
    "Mozzies - AcMedSci GCRF networking grant": "Mozzies Open Philanthropy",
    "PhD - Rachel Lennon": "Rachel Lennon - PhD",
    "PhD – Sophie Mwinyi": "Sophie Mwinyi - PhD",
    "PhD — Hulda": "Hulda Hermannsdottir - PhD",
    "PhD – Ivan Casas Gomez-Uribarri": "Iván Casas - PhD",
    "PhD – Xinyue Jia": "Xinyue Jia – MRes, PhD",
    "MSc - Sasha Chew": "Sasha Chew - MSc",
    "PDR": "Rivka Lim - PDRA",
    "PDRA — Rivka": "Rivka Lim - PDRA",
    "Undergrad - Disease Ecology": "Undergrad",
    "PGT - Ewan Boswell": "PGT",
    "PGT - QMBCE/DSEE": "0. DSEE Admin",
    "PGT – Fundamentals of Programming": "2. Fundamentals of Programming",
    "PGT – Intro to R": "PGT",
    "PGT – Modern Inference": "3. Modern Inference",
    "Apodemus RNA vaccine exWAGO - BBSRC": "Apodemus RNA vaccine exWAGO - BBSRC",
    "Apodemus ageing NERC": "Apodemus ageing - Tom's WT",
    "Apodemus superspreaders NERC": "Apodemus-superspreaders",
    "Apodemus supplementation NERC": "Apodemus-superspreaders",
    "Mus BBSRC Pol III ageing - frailty": "Mus-Hb_Nutrition",
    "Mozzies-AI_MIRS_Royal_Society": "Mozzies-MIRS-AI_Gates Deep Surveillance",
    "Badgers_APHA": "Badgers_APHA",
    "Collège des Réaux-Croix ": "Collège des Réaux-Croix",
    "Collège des Réaux-Croix": "Collège des Réaux-Croix",
    # Julia / package repos on the board — no dedicated OmniFocus project today.
    # Empty TASKS.toml files are no longer auto-created; capture into the inbox instead.
    "CausalDynamics.jl": "CausalDynamics.jl",
    "CausalTargeted.jl": "CausalTargeted.jl",
    "DAGMakie.jl": "DAGMakie.jl",
    "NERC coinfection transmission": "Apodemus coinfection transmission",
}


def fold_title(value: str) -> str:
    """NFC-normalise and strip for tolerant title comparison."""
    return unicodedata.normalize("NFC", (value or "").strip())


def lookup_alias(of_project: str) -> str | None:
    """Resolve ``PROJECT_FOLDER_ALIASES`` with stripped / folded keys."""
    raw = (of_project or "").strip()
    if not raw:
        return None
    if raw in PROJECT_FOLDER_ALIASES:
        return PROJECT_FOLDER_ALIASES[raw]
    folded = fold_title(raw)
    for key, target in PROJECT_FOLDER_ALIASES.items():
        if fold_title(key) == folded:
            return target
    return None


def canonical_board_name(name: str | None, forge_paths: dict[str, object]) -> str | None:
    """Return the board folder spelling when ``name`` matches a Finder project."""
    if not name:
        return None
    want = fold_title(name)
    for key in forge_paths:
        if fold_title(str(key)) == want:
            return str(key)
    return None


def resolve_folder(
    task: dict,
    project_forge: dict[str, str | None],
    forge_paths: dict[str, object],
) -> str | None:
    """Return Forge folder name for an OmniFocus task."""
    if task.get("forgeFolder"):
        return task["forgeFolder"]
    project = task.get("ofProjectName") or ""
    alias = lookup_alias(project)
    if alias is not None:
        return canonical_board_name(alias, forge_paths) or alias
    if project_forge.get(project):
        return project_forge[project]
    board = canonical_board_name(project, forge_paths)
    if board:
        return board
    return None


def keep_task(task: dict, project_ids: set[str]) -> bool:
    """Drop OmniFocus project rows unless they are Forge link sentinels."""
    if task.get("forgeFolder"):
        return True
    return task.get("id") not in project_ids


def is_waiting(task: dict) -> bool:
    blob = f"{task.get('name', '')} {task.get('note', '')}".lower()
    return "waiting for" in blob

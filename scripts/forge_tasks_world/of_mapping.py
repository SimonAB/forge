"""Map OmniFocus projects and tasks onto Forge project folders."""

from __future__ import annotations

PROJECT_FOLDER_ALIASES: dict[str, str | None] = {
    "SLiMs model paper": "SLiMs_manuscript",
    "Oncho MIRS-AI Gates project": "Oncho-MIRS-AI_Gates",
    "Causal Dynamics of Complex Systems (CDCS)": "causal-dynamics-concept-notes",
    "Viral Host Predictor v2": "Viruses-ViralHostPredictor",
    "VectorPredictor": "Viruses-ViralHostPredictor",
    "Activate grant [Wellcome, Leverhulme, ERC] Application": "Apodemus vaccines BIG GRANT",
    "Birds_light_at_night NERC": "ZebraFinches",
    "Zebrafinches transcriptomes NERC": "ZebraFinches",
    "Sunfish - NERC EOI": "ZebraFinches",
    "Lepto Leverhulme app": "Lepto",
    "Wild Vaccines: submit Leverhulme proposal ": "Apodemus vaccines BIG GRANT",
    "Apodemus - Wild Vaccines BIG GRANT - WT discovery, ERC": "Apodemus - Wild Vaccines WT discovery",
    "Apodemus-DTV_Vaccines": "Apodemus vaccines BIG GRANT",
    "Mozzies - Open Philanthropy": "Mozzies Open Philanthropy",
    "Mozzies - AcMedSci GCRF networking grant": "Mozzies Open Philanthropy",
    "PhD - Rachel Lennon": "Rachel Lennon - PhD",
    "PhD – Sophie Mwinyi": "Sophie Mwinyi - PhD",
    "PhD — Hulda": "Hulda Hermannsdottir - PhD ",
    "PhD – Ivan Casas Gomez-Uribarri": "Iván Casas - PhD",
    "PhD – Xinyue Jia": "Xinyue Jia – MRes, PhD",
    "MSc - Sasha Chew": "Sasha Chew - MSc",
    "PDR": "Rivka Lim - PDRA",
    "PDRA — Rivka": "Rivka Lim - PDRA",
    "Undergrad - Disease Ecology": "Undergrad",
    "PGT - Ewan Boswell": "PGT",
    "PGT - QMBCE/DSEE": "PGT",
    "PGT – Fundamentals of Programming": "PGT",
    "PGT – Intro to R": "PGT",
    "PGT – Modern Inference": "PGT",
    "Apodemus RNA vaccine exWAGO - BBSRC": "Apodemus RNA vaccine exWAGO - BBSRC",
    "Apodemus ageing NERC": "Apodemus ageing - Tom's WT",
    "Apodemus superspreaders NERC": "Apodemus-superspreaders",
    "Apodemus supplementation NERC": "Apodemus-superspreaders",
    "Mus BBSRC Pol III ageing - frailty": "Mus-Hb_Nutrition",
    "Mozzies-AI_MIRS_Royal_Society": "Mozzies-MIRS-AI_Gates Deep Surveillance",
    "Badgers_APHA": "Badgers_APHA",
    "Collège des Réaux-Croix ": "Collège des Réaux-Croix",
    # Julia / package repos on the board — no dedicated OmniFocus project today.
    # Empty TASKS.toml files are no longer auto-created; capture into the inbox instead.
    "CausalDynamics.jl": "CausalDynamics.jl",
    "CausalTargeted.jl": "CausalTargeted.jl",
    "DAGMakie.jl": "DAGMakie.jl",
    "NERC coinfection transmission": "Apodemus coinfection transmission",
}


def resolve_folder(
    task: dict,
    project_forge: dict[str, str | None],
    forge_paths: dict[str, object],
) -> str | None:
    """Return Forge folder name for an OmniFocus task."""
    if task.get("forgeFolder"):
        return task["forgeFolder"]
    project = task.get("ofProjectName") or ""
    if project in PROJECT_FOLDER_ALIASES and PROJECT_FOLDER_ALIASES[project] is not None:
        return PROJECT_FOLDER_ALIASES[project]
    if project_forge.get(project):
        return project_forge[project]
    if project in forge_paths:
        return project
    return PROJECT_FOLDER_ALIASES.get(project)


def keep_task(task: dict, project_ids: set[str]) -> bool:
    """Drop OmniFocus project rows unless they are Forge link sentinels."""
    if task.get("forgeFolder"):
        return True
    return task.get("id") not in project_ids


def is_waiting(task: dict) -> bool:
    blob = f"{task.get('name', '')} {task.get('note', '')}".lower()
    return "waiting for" in blob

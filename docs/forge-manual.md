---
title: Forge user manual
---

## Overview

Forge is a local-first project manager that combines:

- A kanban-style board for visualising work-in-progress.
- Finder tags on project folders as the canonical “state”.
- A small menu bar companion and a board window for day-to-day use.

This document explains how Forge fits together and how to use it day-to-day.

## Who is Forge for?

Forge is for people who want a transparent, files-first system:

- Projects are normal folders.
- Project state (columns, flags, assignees) lives in Finder tags.

Forge is a good fit if you:

- Prefer plain-text workflows you can search, diff, and version-control with git.
- Want a kanban view for project flow without a hosted backend.
- Care about local-first privacy and want to avoid hosted task servers.

## Optional: AI assistants and privacy

Some people paste `forge board --json` output or project paths into a coding assistant. For
**privacy**, this project recommends **Ollama** with the **Pi** coding agent
(install Ollama, pull a local model, install `@mariozechner/pi-coding-agent`, then
`ollama launch pi` — see **`PRIVACY.md`**, section **AI assistants and local
language models**, for step-by-step notes and links).

## Core concepts

- **Forge directory**: A folder (often `~/Documents/Forge`) containing:
  - `config.yaml` – Forge configuration.
- **Project roots**:
  - One or more directories (configured in `config.yaml`) under which Forge looks for project folders.
  - By default (`project_scan_depth: 1`), each direct child folder is a project. With `project_scan_depth: 2`, Forge also scans inside **untagged** grouping folders for tagged subfolders (for example manuscript folders inside a research programme directory).
  - Finder tags on each project folder carry the workflow column and any meta/assignee tags.
- **Privacy**:
  - There are no Forge-hosted services: your project data stays on disk as ordinary folders and Finder tags.

## Components

- **CLI (`forge` command)**:
  - `forge board` / `forge board --json` — kanban board (and machine-readable output for scripts).
  - `forge move` — move a project between columns.
  - `forge project-tag` — add/remove/list meta and assignee Finder tags on a project folder.

- **Menubar app (Forge.app)**:
  - Shows a small status icon and quick access to board workflows.

- **Board app (`forge-board`)**:
  - A windowed kanban board for projects, driven by Finder tags.

## Typical workflows

### Delegated work and assignees

- Use **Finder tags starting with `#`** on project folders (for example `#PeggySue`) to mark who a project is delegated to.
- In the **board app**:
  - Use the **Assignee** picker in the toolbar to filter projects by these `#Person` tags.
  - Each project card shows both meta tags and assignee names (as `@Name`).
- In the **CLI**:
  - `forge board --assignee PeggySue` shows only projects tagged with `#PeggySue`.

### 3. Working from the board

- Use `forge board` in the terminal or the Forge board app to see your work laid out in columns.
- Moving projects between columns updates Finder tags on the project folders.

### 3.1 Radar view for projects

- The board toolbar includes a **Radar** picker that slices projects into three buckets:
  - **Calm** – recently-touched, non-urgent projects.
  - **Watch** – projects with no recent activity for roughly a week.
  - **Heat** – explicitly urgent projects (tagged with an `URGENT…` meta tag such as `URGENT ⚠️`), or projects that have been neglected for several weeks.
- Radar combines these signals so you can quickly surface projects that are both **time-sensitive** and **at risk of being forgotten**, without changing any underlying tags or files.

## Where to look when something seems off

- **Projects missing from the board**:
  - Check `config.yaml` to ensure your `project_roots` point at the correct workspace directories.
  - If the project lives inside a grouping folder (not a direct child of a root), set `project_scan_depth: 2`, or add the grouping folder as its own `project_root`.
  - If `project_tag` is set, ensure the project folder carries that Finder tag.

- **Performance issues**:
  - Follow the benchmark checklist in this document.
  - Attach `time forge board` output and any Time Profiler screenshots or call tree summaries.

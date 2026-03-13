---
title: Forge user manual
---

## Overview

Forge is a local-first project and task manager that combines:

- Plain-text markdown files for projects and areas.
- A kanban-style board for visualising work-in-progress.
- Two-way synchronisation with Reminders and Calendar on macOS.
- A small menubar app that keeps everything in sync in the background.

This document explains how Forge fits together and how to use it day-to-day.

## Who is Forge for?

Forge is for people who think in files and folders first, and who already use file attributes and tags to organise their projects and tasks. If you like being able to open a normal directory in Finder or your editor and see exactly where everything lives – with no opaque databases or cloud backends – Forge is designed for you.

More specifically, Forge works well if you:

- Prefer plain-text, markdown-based systems that you can read, search, and version-control with standard tools like git.
- Use or want to use Finder tags (including people-tags like `#Alice`) to track project state, assignees, and meta information.
- Want a files-first, open-source tool that never locks you into a particular app, subscription, or proprietary data format.
- Like the idea of combining a kanban-style view for projects (columns such as Backlog, In Progress, Review, Done) with a GTD-style flow for tasks (inbox, clarify, organise, review, do).
- Need your system to co-exist with other tools – editing markdown in Neovim or VS Code, browsing tasks in Finder, and seeing the same items mirrored into Apple Reminders and Calendar.
- Care about local-first privacy: all of your projects and tasks stay on your Mac as markdown files, with only minimal metadata in a local cache for performance.

In terms of management style, Forge borrows:

- From GTD (Getting Things Done): clear inbox capture, next actions by context (via `@ctx()`), defer and due dates, waiting-for tracking, and regular reviews of areas and projects.
- From kanban and visual flow management: column-based project states driven by Finder tags, explicit work-in-progress visualisation, and quick reassignment of focus by dragging cards between columns.
- From “second brain” / personal knowledge management-style systems: everything lives in durable text files that you can link, reorganise, and refactor over time without losing history or being tied to a single application.

If you want a flexible backbone that supports these paradigms but still allows you to evolve your own naming conventions, folder layouts, and tag schemes over time, Forge aims to give you that structure without forcing a single “correct” organisational system.

## Core concepts

- **Forge directory**: A folder (often `~/Documents/Forge`) containing:
  - `config.yaml` – Forge configuration.
  - `tasks/` – inbox and area markdown files, plus generated artefacts like `due.md`.
- **Project roots**:
  - One or more directories (configured in `config.yaml`) under which Forge looks for `TASKS.md` files.
  - Each `TASKS.md` file represents a project.
- **Areas and inbox**:
  - Area files live in `Forge/tasks/*.md` (excluding special files like `inbox.md`, `someday-maybe.md`, `due.md`).
  - `inbox.md` is the capture point for quick notes and imported Reminders.
- **Sync engine**:
  - `SyncEngine.sync()` is responsible for keeping markdown, Reminders, and Calendar in agreement.
- **Privacy**:
  - All project and area content is stored as plain-text markdown under your Forge directory.
  - Forge maintains a small local SQLite cache at `Forge/.cache/tasks.db` for file metadata and counts only; task text remains in markdown.
  - There are no Forge-hosted services: all synchronisation happens locally between your files and macOS Reminders/Calendar on your machine.

## Components

- **CLI (`forge` command)**:
  - `forge sync` – run a full two-way sync between markdown, Reminders, and Calendar.
  - `forge due` – list overdue and upcoming tasks from markdown (optionally writing `tasks/due.md`).
  - Other commands (`forge board`, `forge process`, etc.) provide various GTD and board views.

- **Menubar app (Forge.app)**:
  - Shows a small status icon with badge counts.
  - Runs background sync every 5 minutes (and once on startup).
  - Provides quick access to capture, processing, board, and review workflows.

- **Board app (`forge-board`)**:
  - A windowed kanban board backed by the same markdown task files.

## How synchronisation works

### What `forge sync` does

When you run:

```bash
forge sync
```

Forge:

- Loads `config.yaml` and resolves the Forge directory and project roots.
- Opens `Forge/.cache/tasks.db` (a small SQLite database that remembers which task files exist and their basic metadata).
- Uses a task index backed by that database to enumerate project `TASKS.md` files under the configured roots.
- Parses project and area markdown into `ForgeTask` objects.
- Fetches Reminders and Calendar events from the configured list and calendar.
- Reconciles in both directions:
  - Markdown → Reminders:
    - Creates reminders for new tasks.
    - Moves reminders to the correct context lists.
    - Marks reminders complete when their corresponding tasks complete in markdown.
  - Markdown → Calendar:
    - Creates or updates events for dated tasks.
    - Removes events when tasks are completed or dates are cleared.
  - Reminders/Calendar → Markdown:
    - Marks tasks complete when reminders complete.
    - Imports new reminders into `inbox.md` when they do not yet exist in markdown.
    - Updates markdown due dates when events move.
- Optionally regenerates `tasks/due.md` and rollup pages, then commits changes to Reminders and Calendar.

### What the menubar app does

When Forge.app (the menubar app) is running:

- On startup:
  - Loads `config.yaml` and finds your Forge directory.
  - Shows the status item and an initial view of counts based on local markdown.
  - Immediately runs `SyncEngine.sync()` once in a background task (with “background” options).
- Every 5 minutes:
  - Runs `SyncEngine.sync()` again with background options.
  - Updates the badge counts by re-reading markdown task files.

Practically, this means that if Forge.app is running:

- Reminders and Calendar will be kept in sync with your markdown tasks without needing to run `forge sync` manually.
- The CLI `forge sync` is still available when you want to force an immediate sync or measure timings from the terminal.

## Typical workflows

### 1. Daily capture and processing

- Use the menubar’s “Quick Capture…” to add ideas into `inbox.md`.
- Capture selections from Mail or Finder into inbox tasks.
- Periodically run:

```bash
forge process
```

from the terminal or via the menubar menu, to empty your inbox and assign tasks to projects or areas.

### 2. Staying on top of deadlines

- Run:

```bash
forge due --markdown
```

to see overdue and upcoming tasks across all projects, and to update `tasks/due.md` for quick reference.

- The menubar badge and menu give a quick summary of:
  - Overdue tasks.
  - Tasks due today.
  - Open inbox items.

### 2.1 Delegated work and assignees

- Use **Finder tags starting with `#`** on project folders (for example `#PeggySue`) to mark who a project is delegated to.
- In the **board app**:
  - Use the **Assignee** picker in the toolbar to filter projects by these `#Person` tags.
  - Each project card shows both meta tags and assignee names (as `@Name`).
- In the **CLI**:
  - `forge board --assignee PeggySue` shows only projects tagged with `#PeggySue`.
  - `forge next --assignee PeggySue` shows next actions assigned to PeggySue (including waiting-for items with `@waiting(PeggySue)`).
  - `forge due --assignee PeggySue` lists due and upcoming items for that person.
  - `forge waiting --assignee PeggySue` narrows the waiting-for list to a single person.

For individual tasks you can also add an explicit assignee in markdown:

```markdown
- [ ] Follow up with Dawn @person(#PeggySue) <!-- id:abc123 -->
```

This keeps the task’s assignee aligned with the same `#Person` convention used for projects.

### 3. Working from the board

- Use `forge board` in the terminal or the Forge board app to see your work laid out in columns.
- Moving tasks between columns updates the underlying markdown and will propagate to Reminders/Calendar on the next sync.

## Where to look when something seems off

- **Tasks missing from reminders or calendar**:
  - Run `forge sync` from the terminal and inspect its output.
  - Check `config.yaml` to ensure project roots and lists/calendars are configured as expected.
  - Verify that the relevant `TASKS.md` or area file lives under a configured project root or `Forge/tasks`.
  - If a new project `TASKS.md` file under an existing project root is not being picked up, run `forge sync --rebuild-index` once to force a full rescan of project roots.

- **Menubar badge counts look wrong**:
  - Ensure Forge.app is allowed to access Reminders and Calendar in System Settings.
  - Wait for at least one background sync cycle (or use “Sync Now” from the menubar menu).
  - Compare output from `forge due` with the badge counts.
  - If CLI due output seems to be missing projects entirely, run `forge due --rebuild-index` to rebuild the cached index of `TASKS.md` files.

- **Performance issues**:
  - Follow the benchmark checklist in this document.
  - Attach `time forge sync` / `time forge due --markdown` output and any Time Profiler screenshots or call tree summaries.

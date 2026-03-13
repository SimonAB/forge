# Forge

Local, markdown-based project and task management for macOS.

Forge combines a **kanban board** for project tracking with a **GTD task manager**
inspired by OmniFocus. Everything lives in plain-text markdown files, editable
with any editor. Two-way synchronisation with Apple Reminders and Calendar keeps
your tasks visible across all your devices.

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

## Components

| Component | Description |
|-----------|-------------|
| [`forge` CLI](docs/cli.md) | Command-line interface for boards, tasks, inbox, sync, and review |
| [Forge.app](docs/app.md) | Menu bar companion — background sync, quick capture, overdue badges |
| [Neovim plugin](docs/neovim.md) | Keymaps, commands, and dashboard integration via `forge-nvim.lua` |

## Quick start

```bash
# On a fresh Mac where Forge source has synced via iCloud Drive:
zsh ~/Documents/Forge/build.sh
```

This builds the Swift project, installs the `forge` binary, creates
`/Applications/Forge.app`, and registers a Launch Agent so the menu bar app
starts at login. The script only touches the Forge source directory,
`~/.forge-build`, and your local application and binary folders; it never sends
any data off your Mac. See [setup details](docs/app.md#setup).

### Requirements

- macOS 14 or later.
- Xcode or Xcode Command Line Tools (for the Swift toolchain).
- Python 3 with Pillow (`pip3 install Pillow`) if you want the generated app icon
  (Forge will still work without this; a default icon is used).

Run `build.sh` once per Mac after your Forge directory has synchronised (for
example via iCloud Drive or git). Your tasks and configuration remain plain-text
files in the Forge directory, shared across machines however you choose to sync.

## Privacy and data model

- All projects, areas, and tasks live as plain-text markdown files in your
  Forge directory (`config.yaml`, `tasks/*.md`, and project `TASKS.md` files).
- Forge keeps a small local cache in `.cache/tasks.db` for performance; this
  stores only file paths, counts, and timestamps, not task text.
- There are **no Forge servers**: the CLI, board, and menu bar app read and
  write only your local files and talk to macOS Reminders and Calendar via
  system APIs on your machine.
- You are free to keep the Forge directory under git, on an encrypted volume,
  or in a local-only folder if you prefer not to sync via any cloud service.

See `PRIVACY.md` for a fuller description of what Forge stores, how sync works,
and how to run in markdown-only or local-only modes.

## Directory layout

```
~/Documents/Forge/              Forge home (synced via iCloud Drive)
├── config.yaml                 Configuration (board columns, contexts, sync targets)
├── inbox.md                    GTD inbox — quick-captured tasks land here
├── someday-maybe.md            Someday / maybe list
├── admin.md                    Area: Admin
├── teaching.md                 Area: Teaching
├── research.md                 Area: Research
├── finance.md                  Area: Finance
├── home.md                     Area: Home
├── personal.md                 Area: Personal
├── spiritual.md                Area: Spiritual
├── horizons.md                 Area: Horizons
├── build.sh                  Per-Mac build & install script
├── generate_icon.py            App icon generator (requires Pillow)
├── import_omnifocus.py         One-time OmniFocus import helper
├── Sources/                    Swift source code
├── Package.swift               Swift package manifest
└── docs/                       Documentation
    ├── cli.md
    ├── app.md
    └── neovim.md

~/Documents/Work/Projects/      Workspace (project directories)
├── ProjectA/
│   └── TASKS.md
├── ProjectB/
│   └── TASKS.md
└── ...
```

Projects are ordinary directories. Their kanban column is stored as a
**Finder tag** (visible in Finder and readable by Spotlight). Each project's
tasks live in a `TASKS.md` file inside the project directory.

## Configuration

Start from [`config.sample.yaml`](config.sample.yaml) and copy it to
`config.yaml`, then adjust paths and names to match your setup. Key sections:

- **`workspace`** — path to the directory containing project folders.
- **`board.columns`** — ordered kanban columns, each mapped to a Finder tag.
- **`board.meta_tags`** — supplementary tags (e.g. Collab, Student, URGENT).
- **`gtd.contexts`** — allowed `@ctx()` values for filtering next actions.
- **`gtd.reminders_list`** / **`gtd.calendar_name`** — Apple integration targets.
  Tasks with an `@ctx()` tag are synced into a separate Reminders list named
  "&lt;reminders_list&gt; • &lt;context&gt;" (e.g. "Forge • email"), so contexts
  appear as lists in the Reminders sidebar.
- **`workspace_tags`** — focus tags that include workspace projects (default:
  `[work]`). Project tasks inherit these tags during sync.
- **`project_areas`** — maps area IDs to project directory names for the
  rollup view (see below).
- **`terminal`** — preferred terminal app (`auto`, `iTerm`, `Terminal.app`).

## Area file frontmatter

Each area markdown file has YAML frontmatter (compatible with Obsidian):

```yaml
---
id: admin
tags: [work]
date_created: 2026-03-07
date_modified: 2026-03-07
---
```

- **`id`** — stable identifier for the area (survives renames).
- **`tags`** — categorise areas for focus sessions (e.g. `work`, `personal`,
  `spiritual`).
- **`date_modified`** — auto-updated by Forge when tasks are added or
  completed; used by `forge review` to flag neglected areas.

## Project rollups

Area files (`research.md`, `admin.md`, etc.) can surface a read-only summary
of tasks from mapped projects. The **Project Tasks** section at the bottom of
each area file is auto-generated — each project heading is a markdown link to
its `TASKS.md` for direct editing.

```bash
forge rollup            # Regenerate all area rollups
```

Rollups are also updated automatically during `forge sync`. Configure the
mapping in `config.yaml`:

```yaml
project_areas:
  research:
  - Lepto
  - Apodemus-virome
  admin:
  - Collaborations
```

## Focus sessions

Focus sessions filter all task-listing commands to show only areas matching
a given tag — useful for dedicated work time, personal errands, etc.

```bash
forge focus work           # Enter work mode — only work areas + projects
forge focus personal       # Enter personal mode — only personal areas
forge focus --clear        # Back to everything
```

The focus persists until cleared. Individual commands also accept `--focus`
for one-off filtering.

## Task format

Tasks are standard markdown checkboxes with inline metadata:

```markdown
- [ ] Write introduction @due(2026-04-01) @ctx(deep-work) <!-- id:a1b2c3 -->
- [ ] Email collaborators @ctx(email) @waiting(Jane) <!-- id:d4e5f6 -->
- [x] Submit abstract @ctx(writing) @done(2026-03-05) <!-- id:789abc -->
```

Supported inline tags: `@defer(DATE)`, `@due(DATE)`, `@ctx(CONTEXT)`,
`@waiting(PERSON)`, `@energy(LEVEL)`, `@repeat(RULE)`, `@done(DATE)`.

### Deferred tasks

A deferred task has a `@defer(YYYY-MM-DD)` date — it is hidden from action
lists until that date arrives. This is the GTD "tickler" / OmniFocus "defer
until" concept: the task exists in your system but only surfaces when it
becomes actionable.

```markdown
- [ ] Prepare conference talk @defer(2026-05-01) @due(2026-06-01) <!-- id:df01ab -->
```

- `forge next` hides deferred tasks by default; use `--deferred` to include them.
- `forge review` shows deferred tasks becoming actionable in the coming week.
- For repeating tasks with both `@defer` and `@due`, the gap is preserved
  when spawning the next instance.
- Defer dates sync to Apple Reminders as the "start date".

### Repeating tasks

Two repeat modes keep recurring tasks alive:

| Syntax | Mode | Next due date |
|--------|------|---------------|
| `@repeat(2w)` | Deferred | Completion date + 2 weeks |
| `@repeat(every 2w)` | Fixed | Previous due date + 2 weeks (skips past today) |

Units: `d` (days), `w` (weeks), `m` (months), `y` (years). Completing a
repeating task automatically creates the next instance in the same file.
Repeat rules sync to Apple Reminders as native recurrence rules.

## Multi-Mac sync

Source code and markdown files sync automatically via **iCloud Drive**. The
compiled `.build` directory is kept outside iCloud at `~/.forge-build` (symlinked
into the source tree). Run `build.sh` on each new Mac to build locally.

## Licence

Forge is distributed under the Apache License, Version 2.0. See the `LICENSE`
file in this repository for the full text.

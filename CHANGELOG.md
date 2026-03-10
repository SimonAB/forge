## Changelog

All notable changes to this project will be documented in this file.

The format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

### [0.6.0] – 2026-03-10

#### Delegated projects and tasks

- Treat Finder tags starting with `#` on project folders (for example `#PeggySue`) as person tags and surface them as `assignees` on `Project` values.
- Extend the kanban board UI to show assignees on project cards and add an **Assignee** filter alongside existing column/meta/domain filters.
- Add assignee support to the board CLI:
  - `forge board --assignee Name` filters projects by `#Name`.
  - The list view shows both meta tags and `@Name` assignees.

#### Task-level delegation and CLI filters

- Extend `ForgeTask` and `MarkdownIO` to support task-level assignees via an inline `@person(#Name)` tag, in addition to existing `@waiting(Name)` semantics.
- Add a shared helper on `ForgeTask` so CLI commands can match both explicit assignees and `waitingOn` names consistently.
- Add `--assignee` filters to:
  - `forge next` – filter next actions and waiting-for items by assignee and show `@Name` alongside existing due/context/waiting labels.
  - `forge due` – filter due and upcoming tasks by assignee and show assignees in the output.
  - `forge waiting` – narrow waiting-for items to a specific person.

#### Delegated overview and menubar integration

- Add a new `forge delegated` command that lists all delegated tasks (non-completed, non-deferred with an assignee) grouped by assignee and then by project/area.
- Extend the menubar app with a Delegation submenu (backed by a small list of favourite assignees) which can open:
  - `forge board --assignee Name`
  - `forge next --assignee Name`
  - `forge waiting --assignee Name`

### [0.5.0] – 2026-03-10

#### Performance

- Introduce a SQLite-backed task file database (`TaskFileDatabase`) to cache project and area task files and their metadata.
- Replace hot-path `TaskFileFinder.findAll` calls with a database-backed `TaskIndex` (`DatabaseTaskIndex`) and a one-off `TaskDiscoveryService`, substantially reducing repeated filesystem walks on `forge sync`, `forge due`, and menubar refresh.

#### Behaviour and architecture

- Wire `SyncEngine`, the CLI `forge sync`/`forge due` commands, and the menubar app to use the database-backed task index for `TASKS.md` discovery.
- Lay the groundwork for future incremental updates and cached counts (via `TaskFileDatabase.filesNeedingParse`, `updateCounts`, and `aggregateCounts`) without changing user-visible behaviour.
- Add documentation for:
  - The task file database and event-driven discovery plan (`docs/task-file-db-plan.md`).
  - A high-level Forge user manual describing core concepts, sync behaviour, and typical workflows (`docs/forge-manual.md`).
  - Updated performance benchmarking guidance that explains how and when Forge syncs with Reminders and Calendar.

### [0.4.0] – 2026-03-10

#### Performance

- Cache project `TASKS.md` discovery via a shared task index to avoid repeated deep filesystem walks (`df0da65`).
- Improve menubar and CLI performance by refining recursive `TASKS.md` discovery under project roots (`f999cc8`, `937bed1`, `c695eec`).
- Make menubar sync lighter while still regenerating the due summary (`95b7ed8`).
- Add several rounds of performance tuning across the CLI and menubar:
  - Limit markdown size and Finder tag operations, and make CLI scans more asynchronous (`48df623`, `7dc44f2`, `501887e`, `ba6bbda`).

#### Behaviour and features

- Improve calendar event deduplication to avoid duplicate events for the same task (`c654a75`, `8253020`).
- Refine inbox processing flow to better fit GTD-style capture and clarify how items move from inbox into projects and areas (`83ae89c`).
- Add markdown due summary generation and integrate it into the sync flow (`279ee93`), producing a `Forge/tasks/due.md` overview.
- Add a dedicated `forge lint` command and `TaskFileLinter` to enforce markdown conventions:
  - Headings and spacing.
  - Placement and formatting of completed tasks.
  - Better handling of mail URLs and list spacing (`be0861c`, `b1d30b6`, `98a9390`, `f9a0cd5`, `d3d0f35`, `1abeee5`, `add8ff7`).
- Enhance capture:
  - Support capture from Bookends and Obsidian (`50865f5`).
  - Add a selection capture feature to inbox for quickly turning selected content into tasks (`99f5f77`).
- Improve CLI and board features:
  - Add `EditTasksCommand` for opening task files from the CLI (`5cbe8d5`).
  - Extend CLI commands to use the shared `taskFilesRoot` for all task-related operations (`ee4aaf9`, `60e8246`).
  - Add and refine the board UI (`6b4fa73`, `02c1616`).

#### Menubar and board app

- Improve the menubar app:
  - Use Forge `tasks` paths consistently for task files.
  - Refine the board window, preferences, and status bar layout (`87dc71e`, `9f9da02`).
  - Fix menubar overdue count and address Calendar sendability warnings (`4a51103`).
- Add a dedicated board app (`forge-board`) backed by the same ForgeCore and ForgeUI components (`6b4fa73`).

#### Configuration and tooling

- Tidy configuration:
  - Simplify project roots and improve shortcuts preferences layout (`250bc69`, `e7f1f26`).
- Update `.gitignore` to better match the Swift/Forge project:
  - Ignore build artefacts, SwiftPM directories, and local `tasks/` content as appropriate (`a573c0d`, `92d2ee5`).
- Add small tooling and release-prep changes:
  - Centralise version information.
  - Provide a help URL and AppleScript usage description.
  - Update the `generate_icon` script (`7767ca9`, `d0b87fa`, `23db3b1`, `a4742ff`).

[0.4.0]: https://github.com/your-org/forge/releases/tag/v0.4.0

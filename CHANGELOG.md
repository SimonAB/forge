## Changelog

All notable changes to this project will be documented in this file.

The format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

### Unreleased

- Preferences window is larger by default (720×560), resizable (min 640×480), and Brief/Workspace panels grow with the window.

### 0.9.2

#### Hermes + local LLM (privacy-first)

- **`docs/hermes.md`** — canonical Hermes + Ollama setup guide; Hermes recommended over Pi for kanban assistant work.
- **`scripts/setup-hermes-forge.py`** — idempotent plug-and-play wiring (`skills.external_dirs`, optional Cursor MCP sample, verification).
- **Forge.app → Preferences → Hermes** — setup status checks, run setup in Terminal, open guide, copy start command.
- **`HermesSetupProbe`** (ForgeCore) — Ollama/Hermes/forge/skill checks for Preferences and diagnostics.
- **`ExecutablePathResolver`** — GUI apps search Homebrew and user bin prefixes (`~/bin`, `~/.local/bin`, …) so Hermes/`forge` checks match an interactive shell; Terminal launches use the same layout.
- **Brief tab** — removed unimplemented External agent option; clarified loopback-only privacy for in-app Ollama briefs.
- Documentation sweep: **`PRIVACY.md`**, **`AGENTS.md`**, **`README.md`**, **`docs/app.md`**, **`docs/cli.md`**, **`docs/forge-manual.md`**, **`docs/index.html`**, **`.cursor/rules/morning-brief.mdc`**.
- Enhanced brief script hardening (`scripts/forge-brief--with-full.py`) — surface board/calendar load warnings; tighter calendar↔project matching.

#### OmniFocus bridge (optional)

- **`forge omnifocus`** — Omni Automation (OmniJS via JXA) bridge: `doctor`,
  `align` (dry-run by default; `--apply` to write), `refresh` (local snapshot),
  `status`, `show`, `proposals` / `apply`.
- **`tag_matching_of_project`** — for structure_hint name matches, propose tagging
  the OF project + active tasks with `🔥 Forge:<name>` (legacy `Forge:` still
  readable; use
  `align --structure-hints-only` to preview just those).
- **`link_tag_root`** — defaults to `🔥 Forge` (matches Finder `project_tag`);
  `legacy_link_tag_roots` keeps older `Forge` tags readable.
- **`column_tag_root`** — nested fallback (`KanbanStatus`; legacy `ForgeColumn` still readable).
- **`flat_column_tags`** (default true) + **`column_tag_aliases`** — use existing OF status
  tags (e.g. `Write ✒️`, `Watch 🚧`) as the sole column markers; nested `KanbanStatus/…`
  is read for migration only. `column_tag_alias_reads` keeps old names readable.
  `align --aliases-only` proposes missing flat tags / strip nested duplicates.
- **`align --column-only`** — propose only kanban-status / Finder column drift fixes.
- **Forge.app Preferences → OmniFocus** — optional toggles for `omnifocus.enabled` and
  `sync_on_move` (writes `config.yaml`; board reloads so the setting takes effect).
- **`sync_on_move`** — gated per-project (ambiguous links only), not board-wide `forge_only`;
  refreshes the local snapshot after a successful mirror. Column writes batch into one
  OmniJS call and resolve tasks via `Task.byIdentifier` when IDs are known.
  Board / menubar moves and Refresh now call the same OmniFocus mirror (previously CLI-only).
- **`sync_from_omnifocus`** (default true) — board **Refresh** pulls OF columns onto Finder;
  `forge omnifocus refresh --apply-finder` does the same from CLI.
- **`sync_completed_project_to_shipped`** (default true) — when an OF *project* is Done/Dropped,
  Refresh moves the matching Finder folder to Shipped.
- **Multi-tag OF tasks** — default resolve keeps Finder’s column when it is among them,
  otherwise the furthest main-flow column. **Refresh pull** prefers a stacked tag that
  *differs* from Finder (e.g. Watch added while Review remains), then strips OF extras
  to that column. Refresh no longer pushes stale Finder columns onto OmniFocus.
- **Menubar OmniFocus Align…** — preview-first sheet; Apply confirms writes.
- **Align ignore list** — `.cache/omnifocus-align-ignore.json` for OF-only noise.
- **Alignment gate** — `sync_on_move` skips OF writes while doctor reports drift
  unless `allow_sync_with_drift` or `forge move --force`.
- **Board JSON** — optional per-project `omnifocus` enrichment from the snapshot cache.
- **Plug-in** — `packaging/omnifocus/` Automation menu helper.

> **Current product:** Finder-tag kanban (`forge` CLI, Forge.app, optional Calendar read,
> optional Ollama Brief, optional OmniFocus bridge). Older changelog entries that mention Reminders, `forge sync`,
> or `TASKS.md` indexing describe historical behaviour.

#### Quality / CI

- **`swift test`** — CLI installer helpers moved into **ForgeCore** so tests no longer
  link Sparkle via `forge-menubar` (fixes test-bundle load failures).
- **CI** — `.github/workflows/ci.yml` runs `swift build`, `swift test`, and
  `python3 -m py_compile scripts/forge-brief.py` on PRs and `main`.

#### CLI

- **`forge move --strict`** — optional workflow guards (one-column steps; Shipped stays
  Shipped; Paused as side column). Default move remains permissive.
- **URGENT detection** — `forge status` / menubar badge use URGENT-prefixed meta tags
  (aligned with Radar), not a single hardcoded string.

#### Documentation / privacy

- **PRIVACY.md** — documents Sparkle updates, Brief→Ollama egress, and `calendar.include`.
- **docs/cli.md** / **docs/app.md** — `forge init`, `scripts/forge-brief.py`, Brief prefs,
  External agent stub.
- **templates/omnifocus** — clarified as optional assistant tooling (no fictional CLI flags).

#### Scripts

- **`forge-brief.py`** — `--calendar-calendars` defaults to empty (all calendars).
- **`build.sh`** — `--no-clean` and `--no-launch-agent` for a faster local loop.

#### Forge.app / packaging

- **Bundled CLI** — `Forge.app` now includes the `forge` binary at `Contents/Resources/bin/forge`.
  Use **Forge → Preferences… → Install CLI…** to put it on your `$PATH` (to `~/bin` or `/usr/local/bin`).
- **Maintainer tooling** — `packaging/package_forge_app.sh` assembles, Developer ID-signs, and optionally notarises the app zip.
- **Privacy** — removed the outdated `NSRemindersUsageDescription` from the generated app `Info.plist`.

#### CLI (prior unreleased)

- **`project_scan_depth`** — optional `config.yaml` setting (default `1`) controlling how many folder levels under each `project_root` Forge scans for tagged projects. Use `2` to discover projects inside untagged grouping folders (for example `Projects/MyGroup/VHP2_manuscript`). Tagged folders are not scanned further. Preferences saves preserve this value.
- **`forge board --json`** — machine-readable kanban: `board.columns`, `meta_tags`, `tag_aliases`, and per-project column, tags, assignees, plus **Radar** fields (`radarBucket`, `daysSinceActivity`, `activityModificationDate`, `activitySource`) aligned with the board UI. **`KanbanRadar`** in ForgeCore centralises Radar logic (also used by **`forge-menubar` / `ForgeUI`**).
- **`forge project-tag`** — `add`, `remove`, and `list` for **meta** and **`#Person`** Finder tags on project directories (`ProjectFolderTagPolicy` validates against `board.meta_tags`; workflow column tags use **`forge move`** only).
- **`forge calendar`** / **`forge events`** — read-only listing of **Apple Calendar** events (EventKit); default window **next 7 days** (`ForgeCalendarDefaults.horizonDays`), with `--days`, `--start` (YYYY-MM-DD), and `--json`.

#### Documentation (prior unreleased)

- **Assistant operating manual** — expanded **`AGENTS.md`** (OmniFocus AppleScript, kanban lifecycle, CLI reference); Cursor rules **`.cursor/rules/forge-cli.mdc`**, **`forge-workflows.mdc`**, **`task-gtd.mdc`**; Hermes skill **`.hermes/skills/forge-board/SKILL.md`**; **`PROJECT_TEMPLATE.md`** for new project READMEs.
- Recommended **Ollama with Pi** for privacy-conscious LLM-assisted workflows; setup
  summary and links in **`PRIVACY.md`**, cross-references in **`README.md`**,
  **`AGENTS.md`**, **`docs/app.md`**, **`docs/cli.md`**, **`docs/forge-manual.md`**, and
  **`.cursor/rules/morning-brief.mdc`**.
- **GitHub Pages** landing page (**`docs/index.html`**) — seventh feature card (**Assistants & LLMs**), hero copy, and meta description highlighting flexible **local vs cloud** assistant choice; stable fragment **`#ai-assistants`** on the privacy page (**`PRIVACY.md`** / **`docs/privacy.html`**).

#### Privacy / packaging

- Documented Calendar read access in **`PRIVACY.md`**; **`NSCalendarsUsageDescription`** added to **`packaging/assemble_forge_app.sh`** for Forge.app.

### [0.9.0] – 2026-03-23

#### Summary

- Opens the **0.9** release line with **Sparkle 2** in-app updates, **`Forge-macos-arm64.app.zip`** on tagged releases, and **CI `generate_appcast`** refreshing **`docs/appcast.xml`**—verified green on **v0.8.14**. See **[0.8.13]** and **[0.8.14]** for full notes.

### [0.8.14] – 2026-03-22

#### Distribution / CI

- **Sparkle appcast** — release workflow runs **`generate_appcast` twice** so **`docs/appcast.xml`** regenerates for ad hoc–signed **`Forge.app`** CI builds (Sparkle’s strict code-sign check on first unarchive; see **`packaging/SPARKLE_SIGNING.md`**).

### [0.8.13] – 2026-03-22

#### Forge.app

- **Sparkle 2** — in-app updates via **`SUFeedURL`** (`docs/appcast.xml` on `main`), **`SUPublicEDKey`**, automatic daily checks (`SUScheduledCheckInterval`), and **Check for Updates…**. **`Sparkle.framework`** is embedded next to the executable (SwiftPM `@loader_path` layout). See **`packaging/SPARKLE_SIGNING.md`** and GitHub secret **`SPARKLE_EDDSA_PRIVATE_KEY`** for release signing.
- Removed the earlier custom GitHub REST + `ditto` updater.

#### Distribution

- **`Forge-macos-arm64.app.zip`** — release workflow builds **`forge-menubar`** (release) and assembles **`Forge.app`** via **`packaging/assemble_forge_app.sh`**, uploaded next to the CLI zip; when the signing secret is set, **`generate_appcast`** refreshes **`docs/appcast.xml`** and the workflow commits it to **`main`** after publishing the release assets.
- **`build.sh`** — delegates app bundle assembly to **`packaging/assemble_forge_app.sh`**.

### [0.8.12] – 2026-03-21

#### Forge.app (menubar and board)

- **Default terminal** — preferences can persist a chosen terminal (`config.yaml` `terminal:`): Auto, Ghostty, kitty, iTerm, Warp, **cmux**, or Terminal. `forge …` and editor launches honour this choice.
- **Vim in terminal** — editor option renamed to **“Vim (in selected terminal)”**; legacy **“Vim (in default terminal)”** still maps correctly.
- **Centralised `EditorLauncher`** — shared open-file/folder logic for the terminal editor and GUI editors.

#### Terminal integration

- **`TerminalLauncher`** — reliable launches per app (Ghostty surface config, kitty remote `launch`, iTerm/Terminal AppleScript, Warp YAML, cmux `new-pane` + `send`, fallbacks).
- **`openNeovim`** — opens the real file with **`cd dir && vim relative-file`** (bare `vim` on `PATH`); kitty still execs the `nvim` binary with a relative file argument.
- **Environment** — resolve **`HOME`** from the login record (`getpwuid`) and set **`XDG_*`** / **`PATH`** so Neovim plugin managers (e.g. lazy.nvim) use the same data dirs as a normal shell.
- **cmux** — warn when socket/automation mode blocks Forge; subprocess env allows automation where needed.

### [0.8.11] – 2026-03-20

#### Distribution

- Ship the pre-built CLI as **Apple Silicon (arm64) only** — single `swift build` on `macos-15`, release asset **`forge-macos-arm64.zip`** (Intel: build from source). Update site and README download links accordingly.

### [0.8.10] – 2026-03-20

#### Distribution

- Run the CLI release workflow on **macos-15** so Swift 6 matches `swift-tools-version 6.0`; keep universal builds via `swift build --triple` for both slices.

### [0.8.9] – 2026-03-20

#### Distribution

- Fix the release workflow: use `swift build --triple` for arm64 and x86_64 (the `--arch` flag is not accepted on the GitHub Actions Swift toolchain).

### [0.8.8] – 2026-03-20

#### Distribution

- Add a GitHub Actions workflow that builds a **universal** (arm64 + x86_64) `forge` CLI on each version tag and attaches **`forge-macos-universal.zip`** to the release (stable URL: `…/releases/latest/download/forge-macos-universal.zip`).
- Add `packaging/README-BINARY.txt` with install and Gatekeeper notes; link the download from the project site hero and the README quick start.

### [0.8.6] – 2026-03-20

#### Documentation and site

- Publish the main documentation as static HTML on the GitHub Pages site (`cli.html`, `app.html`, `neovim.html`, `manual.html`, `privacy.html`, `readme.html`), generated from markdown via `docs/build_site.py` and `docs/requirements.txt` (Python `markdown`).
- Extend the landing page navigation and cross-links to those pages; add shared `assets/theme.js` and prose styles in `assets/site.css`.
- Document regeneration steps and the page ↔ source mapping in the README **Project website** section.

### [0.8.5] – 2026-03-20

#### Documentation and site

- Add a static project landing page under `docs/` for GitHub Pages: hero, feature grid, forge/fire-themed styling (light/dark), quick start, and links to repository docs.
- Promote the live URL in the README and expand the **Project website** section with source file pointers and Pages setup.

### [0.8.4] – 2026-03-20

#### CLI due and review

- `forge due --areas` now considers due dates in all markdown files under `Forge/tasks/`, including `inbox.md` and `someday-maybe.md`, and skips only the generated `due.md` summary (avoids feedback loops).
- `forge review` prints task IDs on key list items so you can jump straight to `forge done` / edits.

### [0.8.3] – 2026-03-18

#### Sync correctness future-proofing

- Prefer a completed duplicate when the same task ID appears multiple times in markdown (so markdown completions propagate correctly).
- Add unit tests around sync input-selection and duplicate handling, plus refactor small decision helpers to be testable.
- Improve future reminder relinking by exposing looser signature helpers for unit testing.

### [0.8.2] – 2026-03-18

#### Menubar correctness and freshness

- Keep menubar overdue / due-today counts aligned with `forge due` by avoiding double-counting and refreshing cached results periodically.
- Make task discovery more robust in the menubar app by falling back to a bounded scan of configured project roots when the task index database is unavailable.

### [0.8.1] – 2026-03-17

#### Menubar and sync correctness

- Fix the menubar dropdown counts (overdue / due today) not always updating after a sync completes.
- Pull reminder due-date changes from Reminders.app back into markdown during sync.
- Ensure the board app’s toolbar refresh runs an in-process background sync (same as the menubar app) before reloading projects.

### [0.8.0] – 2026-03-13

#### Board Radar and delegation polish

- Add a **Radar** filter to the kanban board that slices projects into three buckets based on urgency and neglect:
  - **Calm** – recently-touched, non-urgent projects.
  - **Watch** – projects whose `TASKS.md` has not changed for roughly a week.
  - **Heat** – projects tagged with an `URGENT…` meta tag (for example `URGENT ⚠️`), or projects whose `TASKS.md` has been neglected for several weeks.
- Base neglect scoring on the last modification time of each project's `TASKS.md` file, falling back to the project directory when needed.
- Refine the board toolbar:
  - Replace the generic meta-tag picker with the Radar picker so urgency and neglect are first-class filters.
  - Rename the top-level delegation filter label from "All" to "Delegation" while keeping assignee filtering unchanged.

### [0.7.1] – 2026-03-13

#### Documentation

- Add a “Who is Forge for?” section to the README and user manual, clarifying that Forge is a files-first, tag-driven system combining kanban-style project flow with GTD-inspired task management.

### [0.7.0] – 2026-03-12

#### Linting and task discovery

- Preserve `## Notes` sections in `TASKS.md` files when `forge lint --fix` runs and ensure canonical section order is `Next Actions`, `Waiting For`, `Completed`, `Notes`.
- Tighten heading and list formatting rules:
  - Enforce exactly one empty line above and below headings when surrounded by content.
  - Disallow blank lines between consecutive list items within the same section.
- Enforce trailing whitespace and EOF conventions:
  - Remove trailing spaces and tabs from all lines.
  - Require documents to end with exactly one empty line (a single trailing blank line terminated by a newline).
- Extend the task index to support explicit full rescans:
  - Add a `forceFullRescan` flag on `DatabaseTaskIndex` and thread it through `TaskDiscoveryService`.
  - Expose `--rebuild-index` flags on `forge sync` and `forge due` to force a fresh recursive scan of project roots and rebuild the task index database.

### [0.6.2] – 2026-03-10

#### Menubar and board

- Refresh the kanban board view after each background sync (or “Sync Now”) so that newly applied Finder tags (e.g. column tags) and meta tags appear without reopening the board or restarting the app.

### [0.6.1] – 2026-03-10

#### Privacy, licensing, and install UX

- Clarify Forge’s **local-first, privacy-respecting** data model in the README and manual, including how markdown files, the task file database, and Reminders/Calendar sync fit together.
- Add a dedicated `PRIVACY.md` describing what Forge stores, how sync works via macOS frameworks, and how to run in markdown-only or local-only modes.
- Add an Apache-2.0 `LICENSE` file and link it from the README.
- Update `.gitignore` to exclude `tasks/`, `.cache/`, and local `config.yaml` files so private task content, caches, and machine-specific configuration are not committed.
- Replace the tracked `config.yaml` with a sanitised `config.sample.yaml` that new users can copy and edit locally.

#### Build script and menubar polish

- Harden `build.sh` with a Swift toolchain check and clearer messaging, and warn when the chosen install directory for `forge` is not on `PATH`.
- Improve the Forge.app About panel copy to emphasise that all data stays in your own files.
- Add a small initial-sync window in the menubar app so the first background sync is visible without being modal.

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

[0.8.12]: https://github.com/SimonAB/forge/releases/tag/v0.8.12
[0.8.11]: https://github.com/SimonAB/forge/releases/tag/v0.8.11
[0.8.10]: https://github.com/SimonAB/forge/releases/tag/v0.8.10
[0.8.9]: https://github.com/SimonAB/forge/releases/tag/v0.8.9
[0.8.8]: https://github.com/SimonAB/forge/releases/tag/v0.8.8
[0.8.6]: https://github.com/SimonAB/forge/releases/tag/v0.8.6
[0.8.5]: https://github.com/SimonAB/forge/releases/tag/v0.8.5
[0.4.0]: https://github.com/your-org/forge/releases/tag/v0.4.0

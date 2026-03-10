---
title: Forge task file database and file-event driven discovery
---

## Overview

Goal: replace hot-path recursive filesystem scanning with a persistent task file database kept up to date via file events (FSEvents) and lightweight metadata checks. This should:

- Keep `forge sync`, `forge due`, and the menubar badge responsive on large trees.
- Still find new and changed `TASKS.md` files reliably.
- Concentrate deep scans into rare, explicit maintenance operations.

This document outlines phases, schema, APIs, and integration points.

## Phase 1 – Database foundation

### 1.1 Storage choice

- Use SQLite via `SQLite3` from the system SDK (no extra package dependency).
- One database file per Forge workspace at:
  - `<ForgeDir>/.cache/tasks.db`

### 1.2 Schema v1

Table: `files`

- `path TEXT PRIMARY KEY` – absolute path to markdown file.
- `kind TEXT NOT NULL` – `"projectTasks" | "area" | "inbox"`.
- `label TEXT NOT NULL` – project or area label.
- `projectRoot TEXT NOT NULL` – resolved project root this file belongs to (for projectTasks).
- `mtime REAL NOT NULL` – last modification time (seconds since reference date).
- `size INTEGER NOT NULL` – last known size in bytes.
- `lastSeenAt REAL NOT NULL` – when we last observed this file during any scan.
- `lastParsedAt REAL` – when we last parsed this file for tasks/counts.
- `overdueCount INTEGER NOT NULL DEFAULT 0` – cached per-file overdue count.
- `dueTodayCount INTEGER NOT NULL DEFAULT 0` – cached per-file due-today count.
- `inboxOpenCount INTEGER NOT NULL DEFAULT 0` – cached inbox open tasks (only for inbox).
- `isDeleted INTEGER NOT NULL DEFAULT 0` – logical deletion flag.

Indexes:

- `idx_files_projectRoot_kind` on (`projectRoot`, `kind`, `isDeleted`).
- `idx_files_kind` on (`kind`, `isDeleted`).
- `idx_files_lastParsedAt` on (`lastParsedAt`).

Versioning:

- Use `PRAGMA user_version` to track schema version.
- v1: `user_version = 1`.

### 1.3 Database wrapper API (`TaskFileDatabase`)

Swift façade in `ForgeCore`:

- Creation/open:
  - `init(forgeDir: String)` – opens or creates `<ForgeDir>/.cache/tasks.db`, ensures schema.

- Write operations:
  - `upsertFiles(_ files: [FileRecord])`
    - Inserts or updates rows in `files` by primary key (`path`).
  - `markDeleted(paths: [String])`
    - Sets `isDeleted = 1` and updates `lastSeenAt`.
  - `updateCounts(_ updates: [CountsUpdate])`
    - Sets `overdueCount`, `dueTodayCount`, `inboxOpenCount`, `lastParsedAt`, `mtime`, and `size` for given paths.

- Read operations:
  - `projectTaskFiles(under roots: [String]) -> [FileRecord]`
    - `SELECT * FROM files WHERE kind = 'projectTasks' AND projectRoot IN (...) AND isDeleted = 0`.
  - `areaFiles(forgeDir: String) -> [FileRecord]`
    - `SELECT * FROM files WHERE kind = 'area' AND isDeleted = 0`.
  - `inboxFile(forgeDir: String) -> FileRecord?`
    - `SELECT * FROM files WHERE kind = 'inbox' AND isDeleted = 0 LIMIT 1`.
  - `aggregateCounts() -> (overdue: Int, dueToday: Int, inboxOpen: Int)`
    - Sums corresponding columns over non-deleted files.
  - `filesNeedingParse() -> [FileRecord]`
    - `SELECT * FROM files WHERE isDeleted = 0 AND (lastParsedAt IS NULL OR lastParsedAt < mtime)`.

Data structures:

- `FileRecord`:
  - Mirrors columns in `files` table in a Swift struct.
- `CountsUpdate`:
  - `path`, `overdueCount`, `dueTodayCount`, `inboxOpenCount`, `mtime`, `size`, `parsedAt`.

Concurrency:

- Internally serialise all DB access via a private `DispatchQueue` or a simple lock.
- Do not mark the DB wrapper `Sendable` initially; keep it confined to the creating actor.

### 1.4 Phase 1 deliverables

- `TaskFileDatabase` type implemented and unit-tested (open, insert, query, update, logical delete).
- No behavioural changes in Forge yet – existing `TaskIndex` and scanning continue to be the source of truth.
- A small CLI or debug hook (optionally behind a flag) to inspect DB contents for debugging.

Acceptance criteria:

- Creating a temporary Forge dir and initialising the DB does not crash.
- Inserting and querying a handful of paths behaves as expected in tests.
- The DB file appears under `.cache/tasks.db` and is reused across runs.

## Phase 2 – Discovery and TaskIndex integration (without FSEvents)

Goal: route all project `TASKS.md` discovery and per-file counts through the database while still using traditional scanning as a fallback/maintenance tool.

### 2.1 Discovery service

Introduce `TaskDiscoveryService` in `ForgeCore`:

- Responsibilities:
  - For a set of `resolvedProjectRoots`, perform a **rare** full discovery using `TaskFileFinder.findAll`.
  - Translate discoveries into `FileRecord` rows (kind = `projectTasks`, label = directory name, projectRoot = root).
  - For Forge `tasks` directory:
    - Discover area files and `inbox.md` and upsert them with `kind = "area"` / `"inbox"`.
- API:
  - `discoverProjectsIfNeeded(config: ForgeConfig, db: TaskFileDatabase)`
    - Runs discovery if DB is empty, or if an explicit `force` flag is passed.
  - `refreshAreasAndInbox(forgeDir: String, db: TaskFileDatabase)`

### 2.2 Evolving TaskIndex

Re-purpose `TaskIndex` as a read-only façade over the DB:

- `TaskIndex` no longer performs any filesystem walks directly.
- Implementation:
  - `DatabaseTaskIndex` holds a `TaskFileDatabase` and implements:
    - `projectTaskFiles(for config: ForgeConfig)` querying the DB.
    - Later, `areaFiles` and `inboxFile` if needed.
- `FileTaskIndex` (JSON-based) can be:
  - Either removed, or kept temporarily only for comparison / migration, then deleted once DB-backed index is stable.

### 2.3 Wiring into SyncEngine, forge due, and menubar

#### SyncEngine

- At `SyncEngine` initialisation:
  - Accept a `TaskIndex` (backed by DB).
  - Ensure `TaskDiscoveryService.discoverProjectsIfNeeded` has populated DB rows at least once.
- `findAllProjectTaskFiles`:
  - Delegates to `taskIndex.projectTaskFiles(for: config)` (already done in current code).
- `collectAllTasks` and `refreshDueMarkdownSummary`:
  - Use the list from `TaskIndex` instead of `TaskFileFinder`.
  - Parsing still happens on demand; DB not yet used to cache parsed counts (that arrives in Phase 3).

#### forge due

- Replace `TaskFileFinder.findAll` with `TaskIndex.projectTaskFiles(for:)` and ensure discovery has run once.
- No behavioural change in output; the only change should be reduced scanning once DB is populated.

#### Menubar (`StatusBarController.computeCounts`)

- Use `TaskIndex.projectTaskFiles` for the list of project files, but continue to:
  - `stat` and parse as in the current implementation.
- This phase focuses on **removing the repeated full tree walk**, not yet on caching counts.

### 2.4 Phase 2 deliverables

- All references to `TaskFileFinder.findAll` in hot paths (`SyncEngine`, `DueCommand`, `StatusBarController`) replaced by calls into `TaskIndex` / DB.
- `TaskDiscoveryService` used:
  - On first run.
  - On an explicit command (e.g. `forge rescan-projects`).
- End-to-end tests and manual runs confirm:
  - Same tasks and counts as before.
  - Improved performance relative to original pre-index implementation.

## Phase 3 – Cached counts and minimal rescanning

Goal: stop re-parsing unchanged files on every run and use the DB’s cached counts and timestamps.

### 3.1 Updating counts in the DB

- Extend `SyncEngine.collectAllTasks` and `StatusBarController.computeCounts` to:
  - For each file:
    - Check DB’s `mtime`/`lastParsedAt`.
    - If unchanged: reuse `overdueCount`/`dueTodayCount` from DB instead of parsing.
    - If changed or not yet parsed: parse and call `updateCounts` on the DB.
- For area files and inbox:
  - Similar strategy using `areaFiles` and `inboxFile` queries.

### 3.2 Aggregated counts for the menubar

- Introduce `TaskFileDatabase.aggregateCounts()`:
  - Single query to sum counts across all non-deleted files.
- `StatusBarController.computeCounts`:
  - Becomes a thin wrapper:
    - Ensures discovery has run at least once.
    - Calls `aggregateCounts()` and returns totals.
  - Moves heavy work (parsing changed files) into a background process that periodically calls `filesNeedingParse()` and `updateCounts`.

### 3.3 Phase 3 deliverables

- Menubar uses `aggregateCounts()` and no longer scans or parses in the timer callback.
- `forge due` and `SyncEngine`:
  - Parse only changed files, based on DB state.
- Benchmarks show:
  - Substantial reduction in `MarkdownIO` parsing time on repeated runs with no edits.

## Phase 4 – FSEvents integration

Goal: keep the DB hot in near real-time without needing CLI or timer-driven discovery to spot new/changed files.

### 4.1 Menubar watcher

- Add an `FSEvents`-based watcher in the menubar app:
  - Watch paths:
    - `config.resolvedProjectRoots`
    - `Forge/tasks`
  - On events:
    - For file creation / rename into place:
      - If the file name is `TASKS.md` (or ends with `.md` in `Forge/tasks`), upsert a `FileRecord` with `lastSeenAt = now`, `mtime`/`size` read from `stat`.
    - For modification:
      - Update `mtime` and `size`, leave counts untouched so `filesNeedingParse` can find them.
    - For deletion / rename out:
      - `markDeleted(path:)` in DB.

### 4.2 Background parser

- In the menubar process, run a background task:
  - Periodically query `filesNeedingParse()`.
  - For each such file:
    - Parse tasks with `MarkdownIO`.
    - Compute overdue / due-today (and inbox open) counts.
    - Call `updateCounts`.
  - This keeps `aggregateCounts()` cheap and up to date.

### 4.3 CLI fallback behaviour

- When CLI commands run and the menubar is not active:
  - They can:
    - Stat known paths from DB and mark changed ones for parsing.
    - Optionally perform a **shallow** readdir of roots to detect new `TASKS.md` files (no deep recursion unless counts are suspiciously low).
- This preserves correctness on machines where Forge.app is not running.

### 4.4 Phase 4 deliverables

- Menubar keeps the DB current using FSEvents.
- `StatusBarController` no longer triggers heavy file work; counts come from DB.
- CLI works correctly even without the menubar, using metadata checks and occasional shallow scans.

## Phase 5 – Testing, migration, and rollout

### 5.1 Testing strategy

- **Unit tests**:
  - `TaskFileDatabase` CRUD and aggregate queries on a temporary DB.
  - `TaskDiscoveryService` populating DB from a synthetic directory tree.
- **Integration tests** (where feasible):
  - Simulate adding/removing `TASKS.md` files and assert that:
    - `forge due` sees them after discovery/refresh.
    - Counts match hand-computed expectations.
- **Performance tests**:
  - Synthetic tree with many nested projects:
    - Measure `forge sync` and `forge due` before and after DB usage.
    - Compare Time Profiler traces to ensure `TaskFileFinder.findAll` is no longer hot.

### 5.2 Migration and fallback

- On first DB use:
  - If `tasks.db` is missing or corrupt:
    - Recreate schema and run a one-off full discovery via `TaskDiscoveryService`.
- Feature flag (if needed):
  - Environment variable or config flag to disable the DB and fall back to legacy scanning:
    - Useful while stabilising the new path.

### 5.3 Rollout steps

- Implement Phase 1 and 2 behind the existing `TaskIndex` façade.
- Once stable:
  - Remove JSON-based `FileTaskIndex`.
  - Ensure all hot paths use `TaskFileDatabase` via the new services.

## Next work items (for future sessions)

This section captures the concrete coding tasks that remain, so we can resume implementation later without re-deriving the plan.

### A. Cache per-file counts into the database

**Goal**: avoid re-parsing unchanged files by storing per-file overdue/due-today/inbox counts in `TaskFileDatabase`, and checking timestamps before parsing.

**Tasks:**

1. **Extend parsing code paths to update the DB**

   - In `SyncEngine.collectAllTasks`:
     - For each project `TASKS.md` file:
       - After parsing tasks (the `tasks` array for that file), compute:
         - `overdueCount` = number of tasks where `!isCompleted && isOverdue`.
         - `dueTodayCount` = number of tasks where `!isCompleted && isDueToday`.
       - `stat` the file for `mtime` and `size`.
       - Call `TaskFileDatabase.updateCounts` with a `TaskFileCountsUpdate`:
         - `path`, `overdueCount`, `dueTodayCount`, `inboxOpenCount: 0`, `mtime`, `size`, `parsedAt: now`.

   - In `DueCommand.run`:
     - When parsing each project `TASKS.md` (inside the `for file in indexedProjectFiles` loop), after finishing per-file task scan:
       - Compute per-file overdue/due-today counts in the same way.
       - Update counts in the DB via `TaskFileDatabase.updateCounts`.
     - Optional: only do this when `--markdown` is used, if wanting to minimise writes, but it is safe to always update.

   - In `StatusBarController.computeCounts`:
     - After parsing each project file (where we currently compute `fileOverdue` / `fileDueToday` and update `countsCache`), also:
       - `stat` the file.
       - Call `TaskFileDatabase.updateCounts` with those counts, `mtime`, `size`, and `parsedAt`.
     - For area files and inbox:
       - When parsing:
         - For area files: compute overdue/due-today counts and write them via `updateCounts`.
         - For inbox: compute open inbox tasks and write into `inboxOpenCount`.

2. **Short-circuit parsing using DB timestamps**

   - Add a helper on `TaskFileDatabase` or in a small `TaskFileCache` utility that:
     - Given a `TaskFileRecord` (or path + `mtime`), can determine whether parsing is needed:
       - If `lastParsedAt == nil` or `lastParsedAt < mtime` → needs parse.
       - Else → can reuse cached counts.

   - In `StatusBarController.computeCounts`:
     - At the very start, if `forgeDir` is present and a DB exists:
       - Call `TaskFileDatabase.aggregateCounts()` and return those totals directly.
       - Optionally still maintain `countsCache` as a short-lived in-memory optimisation.
     - Only if DB is unavailable or empty should we fall back to scanning + parsing all files.

   - In CLI paths:
     - `forge sync` and `forge due` can continue to parse files as they do now (for correctness), but:
       - Before parsing a file, they may check DB state and skip parsing if we are satisfied with cached counts.
       - Alternatively, keep CLI behaviour simple and let menubar/background parsing (Phase B) handle most caching.

**Acceptance criteria:**

- Re-running `forge sync` / `forge due` with no file edits shows reduced `MarkdownIO` time in Instruments.
- Menubar `computeCounts` can be changed to a cheap `aggregateCounts()` call in the steady state (once Phase B is in place).

### B. FSEvents watcher and background parser in the menubar

**Goal**: keep `TaskFileDatabase` up to date in near real-time from filesystem changes, so the menubar and CLI can rely primarily on the DB instead of periodic scans.

**Tasks:**

1. **Create a `TaskFileWatcher` for forge-menubar**

   - New type in `Sources/forge-menubar`, macOS-only:
     - Uses `FSEventStreamCreate` to watch:
       - Each path in `config.resolvedProjectRoots`.
       - `ForgePaths(forgeDir:).taskFilesRoot`.
     - Maintains a reference to `TaskFileDatabase`.

   - On FSEvents callback:
     - For each event path:
       - Normalise to a real path (`standardizingPath`).
       - Check whether it is:
         - A `TASKS.md` under a project root.
         - A `.md` file under `Forge/tasks` (area or `inbox.md`).
       - For create/modify:
         - `stat` the file for `mtime` and `size`.
         - Determine `kind` and `label`:
           - `kind = .projectTasks` when under a project root and named `TASKS.md`.
           - `kind = .area` or `.inbox` when under `tasks` directory.
         - Upsert a `TaskFileRecord` with updated metadata and `lastSeenAt = now`.
       - For delete/rename out:
         - Call `TaskFileDatabase.markDeleted(paths: [path])`.

2. **Background parsing loop in `StatusBarController`**

   - In `StatusBarController.start()`:
     - After `loadConfig()` and setting `forgeDir`:
       - Create a shared `TaskFileDatabase` and `TaskDiscoveryService`.
       - Ensure `TaskDiscoveryService.ensureProjectTasksIndexed` has run once.
       - Create a `TaskFileWatcher` with the same DB and config, and start its FSEvents stream.
       - Start a background `Task.detached` that:
         - Loops with a sleep (e.g. `try await Task.sleep(for: .seconds(20))`):
           - Calls `filesNeedingParse()` on the DB.
           - For each record:
             - Parses the file with `MarkdownIO`:
               - For `.projectTasks` / `.area`: compute overdue/due-today counts.
               - For `.inbox`: compute `inboxOpenCount`.
             - Writes updates via `updateCounts`.

3. **Hook menubar counts to DB**

   - Update `StatusBarController.computeCounts` to:
     - Prefer the DB path:
       - If `forgeDir != nil` and DB opens successfully:
         - Return `aggregateCounts()` directly.
       - Optionally use `filesNeedingParse()` to trigger ad-hoc parsing if the background loop is not running.
     - Only fall back to the existing scan+parse path when DB cannot be opened.

**Acceptance criteria:**

- Editing `TASKS.md` or area/inbox files while Forge.app is running:
  - Causes menubar badge counts to update within the background loop interval, without noticeable freezes.
  - `TaskFileDatabase.filesNeedingParse()` reports changed files until parsed, then clears them.
- Deleting or renaming projects/tasks files:
  - Removes them from counts after a short delay, via `markDeleted` + `aggregateCounts()`.

### C. Optional: CLI usage of cached counts

**Goal**: let CLI commands benefit from the DB when menubar is not running, while preserving correctness.

**Ideas:**

- On CLI `forge sync` / `forge due`:
  - Before parsing, open `TaskFileDatabase` and call `filesNeedingParse()`:
    - For files not in that list, trust cached counts for display-only purposes.
    - For files in the list, parse as usual and call `updateCounts`.
  - This keeps CLI correct (because we still parse when needed), but reduces unnecessary parsing when menubar has already done the heavy lifting.

These notes should be enough to resume work later and know exactly where to plug in the remaining pieces (cached counts, FSEvents, background parsing) without having to re-derive the design from scratch.

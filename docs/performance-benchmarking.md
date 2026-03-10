---
title: Forge performance benchmarking
---

# Forge performance benchmarking

Use this document to record benchmarks and profiling notes for Forge, including sync timings and menu bar responsiveness across machines.

## Goals

- Understand where time is spent during sync and startup.
- Track changes in performance over time as code is updated.
- Capture any environment details (macOS version, hardware, iCloud status) that may influence results.

## Benchmark checklist

- Record `time forge sync` (first and second run).
- Record `time forge due --markdown`.
- Note any visible pauses or beachballs when Forge.app starts or syncs in the menu bar.
- Attach Time Profiler screenshots or summaries of the top hotspots.

## How Forge syncs tasks, Reminders, and Calendar

This section documents the current sync model so you can interpret benchmarks correctly and reason about when work actually happens.

### Entities

- **Task files (markdown)**:
  - Project `TASKS.md` files under each configured `project_root`.
  - Area files and `inbox.md` under `Forge/tasks/`.
- **Reminders**:
  - Managed via EventKit (`EKReminder`) through `RemindersBridge`.
- **Calendar**:
  - Managed via EventKit (`EKEvent`) through `CalendarBridge`.

### Core sync engine

All real synchronisation between markdown, Reminders, and Calendar is done by `SyncEngine.sync()`:

- Reads and parses project `TASKS.md` and area files into `ForgeTask`s.
- Fetches Reminders and Calendar events from the configured list and calendar.
- Reconciles in both directions:
  - Markdown → Reminders:
    - Creates/moves/completes Reminders for tasks.
  - Markdown → Calendar:
    - Creates/updates/removes events for dated tasks.
  - Reminders/Calendar → Markdown:
    - Marks tasks complete.
    - Imports new items into `inbox.md`.
    - Updates due dates based on calendar changes.
- Optionally regenerates `Forge/tasks/due.md` (due summary) and rollup files.

All other commands (e.g. `forge due`, `forge board`) are **readers** of markdown (plus derived artefacts) – they do not talk to Reminders or Calendar.

### CLI sync behaviour

- When you run:

  ```bash
  forge sync
  ```

  the `SyncCommand`:

  - Loads `config.yaml`.
  - Resolves the Forge directory and task files root.
  - Opens/creates the task file database under `Forge/.cache/tasks.db`.
  - Constructs a database-backed task index.
  - Builds `SyncEngine(config:…, taskIndex:…)` and calls `await engine.sync()`.

- This is the canonical way to force an immediate, full two-way sync from the terminal.

### Menubar (Forge.app) behaviour

- When Forge.app launches:
  - `StatusBarController.start()`:
    - Loads `config.yaml` and `forgeDir`.
    - Sets up the status item and initial menu.
    - Calls `refreshCounts()` once to compute the badge from local markdown.
    - Starts the background sync timer via `startSyncTimer()`.

- **Cold start sync**:
  - `startSyncTimer()` immediately calls `performBackgroundSync()` once (before the first 5‑minute tick).
  - `performBackgroundSync()`:
    - Opens the task DB and index.
    - Constructs `SyncEngine(config:…, options: .background, taskIndex:…)`.
    - Calls `await engine.sync()`, which performs the same core reconciliation as the CLI sync (with some optional work disabled).
    - Updates `lastSyncDate` and calls `refreshCounts()` so the menubar badge reflects the synced state.

- **Automatic 5‑minute syncs**:
  - After the initial run, the timer fires every `syncInterval` seconds (300s by default).
  - Each tick calls `performBackgroundSync()` again:
    - This again runs `SyncEngine.sync()` with background options, keeping markdown, Reminders, and Calendar aligned.

### What to remember when benchmarking

- **`forge sync` (CLI)**:
  - Runs a full sync once, then exits.
  - Ideal for measuring cold and warm sync costs in isolation.

- **Forge.app (menubar)**:
  - On cold start:
    - Does initial UI + count computation.
    - Then immediately runs a background `SyncEngine.sync()` once.
  - While running:
    - Repeats background sync every 5 minutes.
    - `refreshCounts()` recomputes or reads aggregated counts for the menubar badge.

For performance work, it is useful to distinguish:

- Time spent in `SyncEngine.sync()` (EventKit + markdown work).
- Time spent in `StatusBarController.computeCounts` (reading/parsing markdown + any cached-counts logic).

## Walkthrough:


### 1. Quick CLI benchmarks (no Xcode required)

#### 1.1 Measure full CLI sync cost

In a terminal:

```bash
cd ~/Documents/Forge

# First run (cold-ish)
time forge sync

# Second run (warmer filesystem caches)
time forge sync
```

Note:

- **Real** time is what you feel as latency.
- Compare first vs second run; a big difference means disk I/O / cache effects.

You can do the same for due summary generation:

```bash
time forge due --markdown
```

#### 1.2 Watch where sync spends time (coarse)

Run `forge sync` and, in another terminal, sample the process while it runs:

```bash
pgrep -x forge    # note the PID
sample <PID> 10 -file forge-sync-sample.txt
```

Then open `forge-sync-sample.txt` and look for big stacks in:

- `SyncEngine.sync`
- `MarkdownIO.*`
- `TaskFileFinder.findAll`
- `EventKit` calls (`EKEventStore`, etc.)

---

### 2. Profiling the menubar app with Xcode + Instruments

You’ll get the clearest picture by profiling `forge-menubar` with **Time Profiler**.

#### 2.1 Run `forge-menubar` under Xcode

1. Open the Forge Xcode project.
2. In the scheme selector (top toolbar), choose the **forge-menubar** scheme.
3. Set build configuration to **Release** (if you want realistic timings).
4. Press **Run** once to make sure it launches and finds your `config.yaml`.

Check that:

- The status bar icon appears.
- The initial sync happens (you may see Reminders/Calendar permission prompts if not granted).

#### 2.2 Attach Time Profiler

1. In Xcode, stop the running app if it’s still under the debugger.
2. With `forge-menubar` chosen as the scheme, go to **Product → Profile**.
3. Xcode will build and launch **Instruments**.
4. In Instruments, choose the **Time Profiler** template, then click **Choose**.
5. Click the red **Record** button.

What to do while recording:

- Let the app **start up fully** (this will exercise:
  - `StatusBarController.start()`
  - first `refreshCounts()`
  - first `performBackgroundSync()`).
- Wait for **one or two timer-driven syncs** (5‑minute interval by default; you can shorten it temporarily in code if you want faster feedback).

Then click **Stop**.

#### 2.3 Inspect the results

In the Time Profiler trace:

1. In the left panel, select the **Main Thread**.
2. In the call tree, enable:
   - “Invert Call Tree”
   - “Hide System Libraries”
3. Filter (search box) for:
   - `SyncEngine`
   - `MarkdownIO`
   - `TaskFileFinder`
   - `computeCounts`
4. Look at the **Self Time** / **Total Time** for:
   - `SyncEngine.sync`
   - `SyncEngine.refreshDueMarkdownSummary`
   - `StatusBarController.computeCounts`
   - Any tight loops in `MarkdownIO` or `TaskFileFinder`.

These are your main suspects for freezes / long pauses, especially if they appear under the **Main Thread** with large time percentages.

---

### 3. Profiling menubar from the terminal (if you prefer)

If you prefer not to go via Xcode:

1. Launch `forge-menubar` normally (from `/Applications` or wherever you install it).
2. Find its PID:

   ```bash
   pgrep -x forge-menubar
   ```

3. Use `sample` during startup or just after login:

   ```bash
   sample <PID> 10 -file forge-menubar-startup.txt
   ```

4. Or use the Time Profiler from the command line:

   ```bash
   instruments -t "Time Profiler" -p <PID> -D forge-menubar-trace
   ```

   Then open `forge-menubar-trace.trace` in Instruments and analyse as in 2.3.

---

### 4. What to send back so we can act on it

After running one or two of these:

- For **CLI**:
  - The `time forge sync` output (first and second runs).
- For **Instruments / sample**:
  - The top few hotspots from Time Profiler (function names + percentages), or
  - A snippet of `forge-menubar-startup.txt` showing the largest stacks.

With that data, I can propose specific code changes (off‑main‑thread work, fewer scans, caching patterns) targeted at the actual bottlenecks you’re seeing.

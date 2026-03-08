# Forge CLI

The `forge` command-line tool manages your kanban board and GTD tasks from the
terminal.

```
forge <command> [options]
```

## Commands at a glance

| Command | Purpose |
|---------|---------|
| `forge board` | Display the kanban board |
| `forge projects` | Show tasks per project |
| `forge next` | Show all next actions |
| `forge inbox` | View or capture inbox tasks |
| `forge add` | Add a task to a project |
| `forge done` | Mark a task as completed |
| `forge move` | Move a project between columns |
| `forge status` | Summary dashboard of all projects |
| `forge sync` | Two-way sync with Reminders & Calendar |
| `forge process` | Interactively triage inbox items |
| `forge review` | Guided weekly review checklist |
| `forge waiting` | Show all waiting-for items |
| `forge contexts` | Show tasks grouped by context |
| `forge someday` | View or add to the someday/maybe list |
| `forge rollup` | Update area files with linked project task summaries |
| `forge due` | Show overdue and upcoming due tasks |
| `forge focus` | Enter or clear a focus session |
| `forge init` | Initialise a new Forge workspace |

---

## forge board

Display the kanban board showing projects grouped by column.

```
forge board [--list] [--column <name>]
```

| Option | Short | Description |
|--------|-------|-------------|
| `--list` | `-l` | Compact single-column list instead of the full board |
| `--column` | `-c` | Filter to a specific column (e.g. `Active`, `Write`) |

**Examples:**

```bash
forge board                  # Full board with columns
forge board --list           # Compact list view
forge board -c Active        # Only active projects
```

---

## forge projects

Show tasks grouped by project, with summary counts and status indicators.

```
forge projects [--project <name>] [--column <col>] [--all] [--deferred] [--focus <tag>]
```

| Option | Short | Description |
|--------|-------|-------------|
| `--project` | `-p` | Filter to a single project (substring match) |
| `--column` | `-c` | Filter to a kanban column (e.g. `Active`, `Write`) |
| `--all` | `-a` | Include completed tasks (last 5 shown per project) |
| `--deferred` | `-d` | Include deferred tasks (hidden by default) |
| `--focus` | | Focus on a specific tag (overrides persistent focus) |

Each project is listed with its kanban column, pending/overdue/deferred/done
counts, and tasks grouped by section (Next Actions, Waiting For). Shipped
projects are excluded by default unless `--project` or `--column` is used.

**Examples:**

```bash
forge projects                    # All non-shipped projects with tasks
forge projects -p manuscript      # Drill into one project
forge projects -c Active          # Only active-column projects
forge projects --all              # Include completed tasks
forge projects --deferred         # Show deferred tasks too
```

---

## forge next

Show all next actions across projects and areas.

```
forge next [--project <name>] [--context <ctx>] [--all] [--deferred] [--focus <tag>]
```

| Option | Short | Description |
|--------|-------|-------------|
| `--project` | `-p` | Filter by project name (substring match) |
| `--context` | `-c` | Filter by context (e.g. `office`, `email`) |
| `--all` | `-a` | Include waiting-for items alongside next actions |
| `--deferred` | `-d` | Include deferred tasks (hidden by default) |
| `--focus` | | Focus on a specific tag (overrides persistent focus) |

Tasks are shown grouped by project. Overdue items are marked with a red
indicator, due-today items with yellow. **Deferred tasks** (those with a
`@defer` date in the future) are hidden by default — use `--deferred` to
include them. Shipped and Paused projects are excluded unless `--project` is
used. When a focus session is active (see `forge focus`), only matching areas
and projects are shown.

**Examples:**

```bash
forge next                        # All next actions
forge next -c deep-work           # Only deep-work context
forge next -p "field study"       # Tasks for a specific project
forge next --all                  # Include waiting-for items
forge next --deferred             # Include deferred tasks
forge next --focus personal       # Only personal areas
```

---

## forge inbox

View or capture tasks to the GTD inbox.

```
forge inbox [text...]
```

- **No arguments:** shows all pending inbox items with IDs and due dates.
- **With text:** creates a new task in `inbox.md` with a generated ID.

Inline tags are supported in the text: `@due(DATE)`, `@ctx(CONTEXT)`.

**Examples:**

```bash
forge inbox                             # View inbox
forge inbox "Buy lab supplies"          # Quick capture
forge inbox "Submit form @due(2026-04-01) @ctx(email)"
```

---

## forge add

Add a task directly to a project's `TASKS.md`.

```
forge add <project> <text...>
```

| Argument | Description |
|----------|-------------|
| `project` | Project directory name or unique substring |
| `text` | Task description with optional inline tags |

Supported inline tags: `@defer(DATE)`, `@due(DATE)`, `@ctx(CONTEXT)`,
`@energy(LEVEL)`, `@waiting(PERSON)`, `@repeat(RULE)`. Using `@waiting`
automatically places the task in the Waiting For section. See **Repeating
tasks** and **Deferred tasks** below for details.

**Examples:**

```bash
forge add "field study" "Collect samples @ctx(lab) @due(2026-05-01)"
forge add manuscript "Chase reviewer @waiting(Dr Smith) @ctx(email)"
forge add admin "Submit report @due(2026-03-14) @repeat(every 2w)"
forge add home "Change filters @due(2026-03-07) @repeat(3m)"
forge add admin "Prepare conference talk @defer(2026-05-01) @due(2026-06-01)"
```

---

## forge done

Mark a task as completed by its 6-character ID.

```
forge done <taskID>
```

Searches all project `TASKS.md` files and area markdown files. The task is
checked off (`[x]`) and a `@done(DATE)` tag is appended.

For **repeating tasks**, completing one instance automatically creates the
next instance with a recalculated due date (see **Repeating tasks**). If the
task also has a `@defer` date, the gap between defer and due is preserved in
the next instance.

**Example:**

```bash
forge done a1b2c3
```

---

## forge due

Show overdue and upcoming due tasks across all `TASKS.md` files found
anywhere under `~/Documents`, regardless of nesting depth.

```
forge due [--days <n>] [--areas]
```

| Option | Short | Description |
|--------|-------|-------------|
| `--days` | `-d` | Lookahead window in days (default: 7) |
| `--areas` | `-a` | Also include tasks from Forge area markdown files |

Tasks are grouped into three sections:

1. **Overdue** — due date has passed (red)
2. **Due today** — due date is today (yellow)
3. **Upcoming** — due within the lookahead window (green)

Each task shows its due date, source file label, context, and ID.

The menu bar companion app uses the same recursive scanner, so the
overdue/due-today badge counts in the menu bar always match `forge due`.
Clicking the overdue or due-today item in the menu bar opens `forge due`
in the terminal.

**Examples:**

```bash
forge due                   # Overdue + due within 7 days (TASKS.md only)
forge due -d 30             # Wider 30-day horizon
forge due --areas           # Include area files (inbox, home, etc.)
forge due -d 14 --areas     # 14-day horizon across everything
```

---

## forge move

Move a project to a different kanban column by changing its Finder tag.

```
forge move <project> <column>
```

| Argument | Description |
|----------|-------------|
| `project` | Project directory name or unique substring |
| `column` | Target column name: Plan, Active, Analyse, Write, Review, Shipped, Paused |

Both arguments support prefix matching (e.g. `act` matches `Active`).

**Example:**

```bash
forge move manuscript Review
```

---

## forge status

Display a colour-coded summary dashboard showing project counts per column,
total projects, active count, and URGENT count.

```
forge status
```

---

## forge sync

Two-way synchronisation with Apple Reminders and Calendar.

```
forge sync [--verbose]
```

| Option | Description |
|--------|-------------|
| `--verbose` | Show detailed sync actions |

**What gets synced:**

- All tasks from project `TASKS.md` files and area markdown files.
- Tasks with `@due` dates are created as Reminders and Calendar events.
- Completing a task in Forge marks the corresponding Reminder as complete.
- Completing a Reminder marks the corresponding Forge task as done.
- New items added to the "Forge" Reminders list are imported to the inbox.
- **Context lists:** Tasks are placed in Reminders by `@ctx()` — the base list is
  `reminders_list` (e.g. "Forge"); tasks with a context go into a list named
  "Forge • &lt;context&gt;" (e.g. "Forge • email", "Forge • office"). Lists are
  created on demand. This mirrors your GTD contexts as separate lists in the
  Reminders sidebar.
- Completing a task in Forge marks the corresponding Reminder as complete.
- **Calendar → Markdown:** If you change an event's date in Calendar.app, the next
  sync updates the task's `@due(...)` in the markdown file so due dates stay
  in sync both ways.
- Area tags from YAML frontmatter are propagated to Reminders (notes field),
  Calendar events (title prefix and notes), and Finder tags on area files.
- Project tasks inherit `workspace_tags` from `config.yaml`.

The sync targets are configured in `config.yaml` under `gtd.reminders_list`
and `gtd.calendar_name`.

---

## forge process

Interactively triage inbox items into projects.

```
forge process
```

For each pending inbox task, you are prompted to:

| Input | Action |
|-------|--------|
| Number | Move to the corresponding project's `TASKS.md` |
| `s` | Move to `someday-maybe.md` |
| `d` | Delete (mark as completed in inbox) |
| `k` | Keep in inbox |

---

## forge waiting

Show all waiting-for items across projects and areas.

```
forge waiting [--focus <tag>]
```

| Option | Description |
|--------|-------------|
| `--focus` | Focus on a specific tag (overrides persistent focus) |

Displays each item with the person being waited on, the "since" date if
available, and the task ID. Respects the active focus session.

---

## forge contexts

Show tasks grouped by their `@ctx()` tag.

```
forge contexts [context] [--focus <tag>]
```

| Argument / Option | Description |
|-------------------|-------------|
| `context` | Optional — filter to a single context |
| `--focus` | Focus on a specific tag (overrides persistent focus) |

Without an argument, all contexts are shown. Tasks from Shipped and Paused
projects are excluded. Respects the active focus session.

**Examples:**

```bash
forge contexts              # All contexts
forge contexts email        # Only email context
```

---

## forge someday

View or add to the someday/maybe list.

```
forge someday [text...]
```

- **No arguments:** shows paused projects and pending someday items.
- **With text:** adds a new item to `someday-maybe.md`.

---

## forge rollup

Update area files with read-only project task summaries. Each area file gets
a clearly-delimited **Project Tasks** section at the bottom, listing pending
tasks from mapped projects with markdown links to their `TASKS.md` files.

```
forge rollup [--verbose]
```

| Option | Short | Description |
|--------|-------|-------------|
| `--verbose` | `-v` | Show per-area breakdown |

The mapping between areas and projects is defined in `config.yaml` under
`project_areas`:

```yaml
project_areas:
  research:
  - Lepto
  - Deer-stress
  - Apodemus-virome
  admin:
  - Collaborations
  - Studentships
```

**Generated section format:**

The rollup section is enclosed in HTML comment markers and regenerated on each
run — manual edits within it are overwritten:

```markdown
<!-- forge:rollup -->

## Project Tasks

> Auto-generated by `forge rollup` — edit tasks in each project's TASKS.md.

### [Lepto](../Work/Projects/Lepto/TASKS.md) · Active — 2 pending

- [ ] Review latest sequencing results — due 2026-03-15 — @lab
- [ ] Sequencing results from core facility — ⏳John

<!-- /forge:rollup -->
```

The project headings are markdown links to the project's `TASKS.md`, making
them clickable in most editors and followable with `gf` in Neovim.

Rollups are also regenerated automatically during `forge sync`.

**Example:**

```bash
forge rollup                  # Update all area rollups
forge rollup --verbose        # Show per-area breakdown
```

---

## forge focus

Enter, check, or clear a focus session. A focus session filters all
task-listing commands (`next`, `contexts`, `waiting`) to only show areas
whose frontmatter tags match the given tag.

```
forge focus [tag] [--clear]
```

| Argument / Option | Description |
|-------------------|-------------|
| `tag` | Tag to focus on (e.g. `work`, `personal`). Omit to show current focus. |
| `--clear` | Clear the active focus session |

The focus is persistent — it's stored in a `.focus` file in the Forge
directory and applies to all subsequent commands until cleared.

**How area tags work:**

Each area markdown file has YAML frontmatter with a `tags` field:

```yaml
---
id: admin
tags: [work]
date_created: 2026-03-07
date_modified: 2026-03-07
---
```

When you run `forge focus work`, only areas tagged `work` are shown. Workspace
projects (directories in the workspace path) are included when the focus tag
matches one of the `workspace_tags` in `config.yaml`.

**Tag assignments:**

| Tag | Areas |
|-----|-------|
| `work` | admin, teaching, research, inbox |
| `personal` | home, finance, personal, horizons, inbox |
| `spiritual` | spiritual |

**Examples:**

```bash
forge focus                  # Show current focus and available tags
forge focus work             # Enter work focus — see only work areas + projects
forge focus personal         # Enter personal focus — see only personal areas
forge focus --clear          # Clear focus — show everything
forge next --focus spiritual # One-off filter without setting persistent focus
```

---

## forge review

Guided weekly review with an 8-step checklist.

```
forge review
```

**Steps:**

1. **Inbox** — reports unprocessed item count
2. **Overdue** — lists all overdue tasks across projects and areas
3. **Due this week** — lists tasks due within the next 7 days
4. **Waiting for** — lists all delegated items
5. **Stalled projects** — flags active projects with no next actions
6. **Becoming actionable** — lists deferred tasks surfacing this week
7. **Neglected areas** — flags area files not modified in over 2 weeks
   (uses `date_modified` from YAML frontmatter)
8. **Someday/Maybe** — counts someday items and paused projects

Concludes with a summary line of key counts.

---

## Deferred tasks

A deferred task has a `@defer(YYYY-MM-DD)` tag — the "start date" or "defer
until" date. The task exists in your system but is hidden from action lists
until the defer date arrives. This is the GTD tickler concept, matching
OmniFocus's "defer until" feature.

### Behaviour

- **`forge next`** hides deferred tasks by default. Use `--deferred` to
  include them, shown with a `deferred until YYYY-MM-DD` label.
- **`forge contexts`** and **`forge waiting`** also hide deferred tasks.
- When a deferred task's date arrives, it automatically appears in your action
  lists — no manual intervention needed.
- Tasks whose defer date is *today* show an `AVAILABLE TODAY` indicator.
- **`forge review`** includes a "Becoming actionable this week" step that
  lists deferred tasks surfacing in the next 7 days.

### Sync with Reminders

The defer date maps to the Reminder's **start date** (`startDateComponents`
in EventKit). Reminders imported from Reminders.app that have a start date
will have that date preserved as `@defer`.

### Combining with repeating tasks

When a repeating task has both `@defer` and `@due`, completing it preserves
the gap between the two dates. For example, a task deferred 1 week before its
due date will have the next instance deferred 1 week before the new due date.

### Example

```markdown
- [ ] Prepare conference talk @defer(2026-05-01) @due(2026-06-01) @ctx(deep-work) <!-- id:df01ab -->
- [ ] Review insurance policy @defer(2026-09-01) @due(2026-10-01) @repeat(every y) <!-- id:df02cd -->
```

---

## Repeating tasks

Forge supports two types of repeating tasks using the `@repeat()` inline tag.

### Syntax

| Tag | Meaning |
|-----|---------|
| `@repeat(2w)` | Repeat 2 weeks **after completion** (deferred) |
| `@repeat(every 2w)` | Repeat every 2 weeks from the **due date** (fixed schedule) |
| `@repeat(d)` | Daily from completion |
| `@repeat(every m)` | Monthly on a fixed schedule |

**Units:** `d` (days), `w` (weeks), `m` (months), `y` (years). The number
defaults to 1 if omitted (e.g. `@repeat(w)` = weekly).

### Behaviour on completion

When you run `forge done` on a repeating task:

1. The current instance is marked done (checkbox ticked, `@done` date added)
   and moved to the Completed section.
2. A **new instance** is created in the Next Actions section with:
   - A fresh task ID.
   - The same text, context, energy, and repeat rule.
   - A recalculated `@due` date.

**Deferred mode** (`@repeat(2w)`): the new due date is calculated from the
completion date. E.g. if completed today, the next instance is due in 2 weeks.

**Fixed mode** (`@repeat(every 2w)`): the new due date is calculated from the
previous due date, advancing forward until it falls after the completion date.
This keeps tasks anchored to their original schedule.

### Sync with Reminders

Repeat rules are mapped to native `EKRecurrenceRule` entries on Apple
Reminders. Rules coming from Reminders into Forge default to fixed-schedule
mode, since EventKit does not distinguish "defer again" from "fixed".

### Example in markdown

```markdown
## Next Actions
- [ ] Submit fortnightly report @due(2026-03-14) @repeat(every 2w) @ctx(email) <!-- id:rp01ab -->
- [ ] Change water filter @due(2026-06-01) @repeat(3m) <!-- id:rp02cd -->
```

---

## forge init

Initialise Forge in a workspace directory.

```
forge init [--workspace <path>]
```

Creates the `Forge/` directory with `config.yaml`, `inbox.md`, and
`someday-maybe.md`. If already initialised, runs tag cleanup (resolving any
tag aliases).

---

## Configuration: project roots

Set **`project_roots`** to a list of paths. Each path’s direct children are
scanned as Forge projects (and filtered by `project_tag` if set). The first
path is used as the primary workspace (e.g. for resolving the Forge directory
when not found via config location).

When **`project_tag`** is set (e.g. `"🔥 Forge"`), only direct children of each root that have that tag are included. Add multiple roots (e.g. `~/Documents/Sanctum`) to include more top-level project folders.

**Example:**

```yaml
project_roots:
  - ~/Documents/Work/Projects
  - ~/Documents/Sanctum
  - ~/Documents/Home
project_tag: "🔥 Forge"   # only folders with this tag are projects
```

Paths support `~` for the home directory. All commands that list projects
(board, next, projects, due, done, sync, status, etc.) use the union of
projects from every listed root.

**Legacy:** Configs that only have `workspace: <path>` (no `project_roots`)
are still read; Forge treats it as `project_roots: [<path>]`.

# Forge CLI

The `forge` command-line tool manages the **project** kanban board from the
terminal: folders and **Finder tags**. Day-to-day tasks can live in OmniFocus,
Reminders, Things, or similar. Commands read and write local state only.

## Installing the CLI

Forge bundles the `forge` binary inside **Forge.app** at `Contents/Resources/bin/forge`.

To put `forge` on your `$PATH`:

1. Open **Forge → Preferences…**
2. Under **Command-line tool (forge)**, click **Install CLI…**
3. Choose:
   - `~/bin` (no admin), or
   - `/usr/local/bin` (admin)

To remove it later, use **Uninstall CLI…** in the same Preferences section.

```
forge <command> [options]
```

## Commands at a glance

| Command | Purpose |
|---------|---------|
| `forge init` | Scaffold a Forge workspace (`config.yaml` and folders) |
| `forge board` | Display the kanban board |
| `forge move` | Move a project between columns |
| `forge project-tag` | Add, remove, or list meta / assignee Finder tags on a project folder |
| `forge archive` | Apply due `Completed` meta tags on Shipped projects (after the delay) |
| `forge status` | Summary dashboard of all projects (column counts, active, URGENT) |
| `forge dashboard` | GTD dashboard — projects, calendar, due tasks from task index (`--json` for Forge.app) |
| `forge calendar` / `forge events` | List upcoming Calendar events (read-only; same command) |
| `forge edit` | Open files/folders in the terminal editor (vim/Neovim; honours `terminal:`) |
| `forge omnifocus` | Optional OmniFocus bridge (`doctor`, `align`, `refresh`, …) |
| `forge reminders` | Optional Apple Reminders bridge (`list`, `status`, `show`, `refresh`, `doctor`, `align`, `paint-colours`, `paint-priorities`) |
| `forge fs` | Nexus sidecar ↔ local tags (`doctor`, `sync`, `migrate`) — see [nexus.md](nexus.md) |
| `forge superproductivity` | Optional Super Productivity task backend (`mirror-menu-tree` mirrors Finder folders into the SP sidebar) |

Read-only brief (Python helper, not a `forge` subcommand):

```bash
python3 scripts/forge-brief.py
```

---

## forge init

Create a new Forge workspace directory with a starter `config.yaml`.
If `config.yaml` already exists, the command reports that Forge is initialised
and runs tag cleanup instead of overwriting the config.

```
forge init [--workspace <path>]
```

---

## forge board

Display the kanban board showing projects grouped by column.

```
forge board [--list] [--json] [--column <name>] [--assignee <person>]
```

| Option | Short | Description |
|--------|-------|-------------|
| `--list` | `-l` | Compact single-column list instead of the full board |
| `--json` | | Print JSON: `board.columns` (names and Finder tags), `meta_tags`, `tag_aliases`, `archiveAfterShippedDays`, `completedMetaTag`, and each project’s column, tags, assignees, plus **Radar** fields and optional **completion** fields (`archiveStatus`, `daysUntilArchive`, `shippedAt`) |
| `--column` | `-c` | Filter to a specific column (e.g. `Active`, `Write`) |
| `--assignee` | `-a` | Filter to projects with this assignee (matches `#Person` Finder tags) |

**Examples:**

```bash
forge board
forge board --list
forge board --json
forge board --json -c Write
```

---

## forge move

Move a project to a different kanban column by changing its Finder tag.

```
forge move <project> <column> [--strict]
```

| Argument / option | Description |
|----------|-------------|
| `project` | Project directory name or unique substring |
| `column` | Target column name (must match configured column names) |
| `--strict` | Enforce left-to-right workflow (one column at a time; Shipped stays Shipped; Paused is a side column) |

By default any configured column is allowed (scripts and power users stay
unblocked). Use `--strict` when you want the documented kanban transition rules.

**Example:**

```bash
forge move manuscript Review
forge move manuscript Write --strict
```

---

## forge archive

Apply the delayed **Completed** meta tag on **Shipped** projects once
`board.archive_after_shipped_days` (default 7) have elapsed. Board **Refresh**
runs the same sweep. Requires a `Completed…` entry in `board.meta_tags`.
Legacy `Archived…` tags on Shipped folders are migrated to Completed.

```
forge archive
forge archive --dry-run
```

| Option | Description |
|--------|-------------|
| `--dry-run` | List Shipped projects with countdown / due / already-completed status; do not write Finder tags |

Ship dates live in `.cache/shipped-at.json`. Legacy Shipped folders without a
cache entry use folder activity age; if already older than the delay, they are
tagged on the next sweep.

**Examples:**

```bash
forge archive --dry-run
forge archive
```

---

## forge project-tag

Add, remove, or list **Finder tags** on a project directory for **meta** (`board.meta_tags`) and **assignee** (`#Name`) labels. **Kanban column** (workflow) tags are only changed with **`forge move`** — this command refuses workflow tags so column state stays consistent.

```
forge project-tag add <project> <tag> [--force]
forge project-tag remove <project> <tag> [--force]
forge project-tag list <project> [--json]
```

| Subcommand | Arguments | Description |
|------------|-----------|-------------|
| `add` | `<project>`, `<tag>` | Adds the tag if not already present. Without `--force`, the tag must be listed in `board.meta_tags` or be a `#Person` assignee tag. |
| `remove` | `<project>`, `<tag>` | Removes the tag by exact string match. Same validation as `add`. |
| `list` | `<project>` | Prints all Finder tags with a **kind** hint: `column`, `meta`, `assignee`, `project_scope` (if `project_tag` in config), or `other`. |

| Option | Description |
|--------|-------------|
| `--force` | On **add** / **remove**, allow tags not in `meta_tags` and not `#…` assignee (e.g. legacy labels). **Workflow column tags are still rejected** — use `forge move`. |
| `--json` | On **list**, print `{ "project", "path", "tags": [{ "name", "kind" }] }`. |

**Examples:**

```bash
forge project-tag list "Oncho-MIRS-AI_Gates"
forge project-tag add "Oncho-MIRS-AI_Gates" "URGENT ⚠️"
forge project-tag remove Apodemus-DTV_Vaccines "URGENT ⚠️"
forge project-tag list SomeProject --json
```

---

## forge calendar / forge events

List upcoming events from **Apple Calendar** (read-only). **`forge events`** is an alias for **`forge calendar`** — use whichever you prefer. By default the window is the **next 7 days** from the start of today (local timezone).

Uses EventKit on your Mac; nothing is written to Calendar. Optional `calendar.include` in
`config.yaml` restricts which calendar **titles** are read (exact match); if
empty or omitted, all event calendars are used.

```
forge calendar [--days <n>] [--start YYYY-MM-DD] [--json]
forge events   [--days <n>] [--start YYYY-MM-DD] [--json]
```

| Option | Description |
|--------|-------------|
| `--days` | Number of calendar days in the window from the anchor day’s midnight (default: **7**) |
| `--start` | Anchor day as `YYYY-MM-DD` (default: today) |
| `--json` | Structured JSON output |

**Examples:**

```bash
forge calendar              # Next 7 days (default)
forge events                # Same as forge calendar
forge calendar --days 14 --start 2026-04-14
forge calendar --json       # Structured output for assistants
```

---

## forge status

Print a compact histogram of projects per column, total/active counts, and how
many projects carry an **URGENT**-prefixed meta tag.

```
forge status
```

---

## forge edit

Open files or directories in the terminal editor (`vim` on `PATH`, typically Neovim).
Uses the same launch path as Forge board “open in Vim”: when `terminal:` is
`auto` (or `herdr` / `tmux`), prefers a live Herdr or tmux session, otherwise
Ghostty / kitty / iTerm / Warp / Terminal.

```
forge edit [paths…] [--terminal <name>]
```

| Option | Description |
|--------|-------------|
| `paths…` | Files or directories. When omitted, opens the home directory. |
| `--terminal` | Override `config.yaml` `terminal:` (`auto`, `herdr`, `tmux`, `Ghostty`, …) |

**Examples:**

```bash
forge edit README.md
forge edit ~/Documents/Software/Forge
forge edit notes.md --terminal herdr
```

Finder “Open With” can use **NeoVim launcher.app**, which should call
`forge edit` (absolute path recommended; Automator’s `PATH` is thin).

---

## forge dashboard

Unified GTD overview: kanban load, URGENT/stuck projects, today's calendar, and due tasks from `.forge/world.db` (via `scripts/forge-dashboard.py`).

```
forge dashboard
forge dashboard --layout split --show 10
forge dashboard --json
forge dashboard --refresh
```

Left-click the menubar hammer in **Forge.app** to open the same snapshot in a popover. Right-click for the menu (**Dashboard…** is also ⌘⇧D).

---

## scripts/forge-brief.py

Read-only operational brief built from `forge board --json`, optional
`forge calendar --json`, and the **task index** (`.forge/world.db`).
Surfaces due/overdue tasks, URGENT items, neglected projects, stuck
in-flight work, column load, and hygiene notes.

```bash
python3 scripts/forge-brief.py
python3 scripts/forge-brief.py --stale-days 5 --show 8
python3 scripts/forge-brief.py --due-days 7
python3 scripts/forge-brief.py --calendar-calendars "Work,Teaching"
```

With an empty `--calendar-calendars` (the default), all calendars returned by
`forge calendar` are included. Restrict titles with a comma-separated list when needed.

Populate the task index first with `bash scripts/morning-review-pull.sh` (sync + brief bundle), or
`python3 scripts/sync-of-tasks-from-of.py` / `python3 scripts/forge-tasks-world.py ingest`.

**Morning review bundle:**

```bash
bash scripts/morning-review-pull.sh
```

Runs OF refresh for the kanban join, skips OmniFocus → `TASKS.toml` when Super
Productivity is the enabled task store, then `forge-brief.py --calendar-days 1`.
GitHub checks stay with the synthesising agent.

This is **not** a `forge` subcommand; it requires `forge` on your `$PATH`.

---

## Tasks (Super Productivity) + legacy TASKS.toml

With `superproductivity.enabled`, capture and inbox go to **Super Productivity**;
briefs read inbox/dues from SP. Forge remains kanban-only. Full behaviour and
planned retirement of `TASKS.toml`: [superproductivity.md](superproductivity.md).

Map folder names in `project_ids` (exact SP project titles). Create missing
projects in the app or via `scripts/sp-plugins/forge-bulk-projects.zip` (Local
REST cannot create projects). Sidebar folders mirror Finder paths:

```bash
forge superproductivity mirror-menu-tree --dry-run
python3 scripts/forge-sp-menu-tree.py --forge-home .   # apply (needs websocket-client)
```

```bash
forge capture "…" --source assistant          # → SP Inbox when enabled
forge tasks inbox
forge tasks assign <id> "Project Name"        # needs project_ids
python3 scripts/forge-brief.py --calendar-days 1
```

Legacy (SP disabled): `<project>/TASKS.toml` and `.forge/tasks.db`.

```bash
python3 scripts/sync-of-tasks-from-of.py          # OmniFocus → TASKS.toml + index
python3 scripts/forge-tasks-world.py ingest
python3 scripts/forge-tasks-world.py due --days 14
```

---

## scripts/forge-dashboard.py

Live terminal dashboard combining kanban, calendar, and due tasks (SP when enabled).

```bash
python3 scripts/forge-dashboard.py --layout compact
forge dashboard --layout split
forge dashboard --json
```

---

## Hermes + Ollama (local assistant)

Privacy-first interactive kanban assistant. Plug-and-play setup from your Forge directory:

```bash
python3 scripts/setup-hermes-forge.py
hermes skills list | grep forge-board
```

See **`docs/hermes.md`**. Forge.app → Preferences → **Hermes** runs the same checks.

---

## forge fs

Portable kanban sidecar (`<project>/.forge/kanban.toml`) ↔ local folder tags.
See [nexus.md](nexus.md) and [omarchy.md](omarchy.md).

```
forge fs doctor [--json]
forge fs sync [--prefer sidecar|finder] [--apply] [--json]
forge fs migrate [--apply] [--overwrite] [--json]
```

`sync` and `migrate` are dry-run unless `--apply`. After Dropbox/git/LocalSend,
run `forge fs sync --apply` so each OS paints its native tags from the sidecar.

---

## forge omnifocus

Optional OmniFocus bridge via Omni Automation (OmniJS). Mirrors **project**
column and link tags. Day-to-day tasks stay in OmniFocus (or Reminders, Things,
or another app). Requires
`omnifocus.enabled: true` in `config.yaml`. Mutating commands **default to
dry-run**; pass `--apply` (and confirm, unless `--yes`) before anything is written
to OmniFocus or Finder tags. `refresh` updates the local
`.cache/omnifocus-snapshot.json`; with `--apply-finder` it also pulls OF columns
onto Finder (when `sync_from_omnifocus` is true). Board **Refresh**
does the same pull (and strips leftover OF kanban tags on folders it updated).
Finder→OF writes happen on `forge move` / board drag when `sync_on_move` is on.

```
forge omnifocus doctor [--json] [--live]
forge omnifocus align [--json] [--apply [--yes]] [--prefer finder|omnifocus] [--structure-hints-only] [--column-only] [--migrate-columns-only] [--aliases-only]
forge omnifocus refresh [--apply-finder]
forge omnifocus status
forge omnifocus show <project> [--live]
forge omnifocus proposals [--json]
forge omnifocus apply [--apply [--yes]]   # same as align; dry-run unless --apply
```

Typical first-time flow:

```bash
forge omnifocus doctor
forge omnifocus align          # review the plan
forge omnifocus align --apply  # confirm when prompted
```

See `packaging/omnifocus/README.md` for the optional Automation plug-in and tag
conventions (`🔥 Forge:…` by default, legacy `Forge:…` still readable; flat `column_tag_aliases` such as `Watch 🚧` when `flat_column_tags` is true; nested `KanbanStatus/…` / legacy `ForgeColumn/…` for fallback and migration).

---

## forge reminders

Optional Apple Reminders **task backend** via EventKit. Reminder *lists* match
Forge project folders by title. Requires `reminders.enabled: true` in
`config.yaml` (or **Forge → Preferences → Reminders**).

Forge.app refreshes `.cache/reminders-snapshot.json` so the CLI can run without
Reminders permission in Terminal. Pass `--live` to force EventKit. `refresh`
writes the snapshot, paints list colours, and sets sentinel priority from Finder
URGENT (requires Reminders permission for the terminal, or use Forge.app →
Preferences → Reminders → Refresh now). Create missing lists
with `forge reminders align --apply`.

`forge reminders status` still runs when Reminders is disabled.

`doctor` compares Forge folders with Reminders lists. `align` previews create-list
(and sentinels when column sync is on); `--apply` requires typing `apply` unless
`--yes` is passed. List colour follows the Finder column on create, on
`forge move`, and on **Refresh** / `forge reminders refresh`. Finder `URGENT ⚠️`
sets high priority on the list’s sentinel (Refresh, `paint-priorities`,
`forge project-tag`, `forge move`).

When Reminders is enabled and the snapshot is eligible, `forge board --json`
includes a `reminders` object per matched folder (`incompleteCount`,
`nextReminder`, `due`, `snapshotAgeSeconds`).

```
forge reminders [--json] [--list NAME] [--project SUB] [--completed] [--live]
forge reminders status
forge reminders show <project> [--json] [--completed] [--live]
forge reminders doctor [--json] [--live]
forge reminders align [--json] [--live] [--apply [--yes]]
forge reminders paint-colours [--live] [--apply [--yes]]
forge reminders paint-priorities [--live] [--apply [--yes]]
forge reminders refresh [--apply-finder]
```

See [Reminders](reminders.md).

---

## Configuration: project roots

Set **`project_roots`** to a list of paths. Forge scans each root for project
folders up to **`project_scan_depth`** levels (default `1` = direct children only).
The first path is used as the primary workspace (e.g. for resolving the Forge
directory when not found via config location).

When **`project_tag`** is set (e.g. `"🔥 Forge"`), only directories with that
tag qualify as projects. With **`project_scan_depth: 2`**, untagged folders under
a root act as grouping containers: Forge scans inside them for tagged subfolders
(e.g. `Projects/Viruses-ViralHostPredictor/VHP2_manuscript`). A tagged folder is
not scanned further (it is treated as the project). Add multiple roots (e.g.
`~/Documents/Sanctum`) to include more top-level project folders.

**Example:**

```yaml
project_roots:
  - ~/Documents/Work/Projects
  - ~/Documents/Sanctum
  - ~/Documents/Home
project_scan_depth: 1     # use 2 for one level of grouping folders
project_tag: "🔥 Forge"   # only folders with this tag are projects
```

Paths support `~` for the home directory. All commands that list projects
(board, status, etc.) use the union of projects from every listed root.

**Legacy:** Configs that only have `workspace: <path>` (no `project_roots`)
are still read; Forge treats it as `project_roots: [<path>]`.

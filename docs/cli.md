# Forge CLI

The `forge` command-line tool manages your kanban board from the terminal,
operating directly on your project folders and their **Finder tags**. There are
no remote services; commands read and write only local state.

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
| `forge status` | Summary dashboard of all projects (column counts, active, URGENT) |
| `forge calendar` / `forge events` | List upcoming Calendar events (read-only; same command) |

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
| `--json` | | Print JSON: `board.columns` (names and Finder tags), `meta_tags`, `tag_aliases`, and each project’s column, tags, assignees, plus **Radar** fields (`radarBucket`, `daysSinceActivity`, `activityModificationDate`, `activitySource`) |
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

## scripts/forge-brief.py

Read-only operational brief built from `forge board --json` (and optionally
`forge calendar --json`). Surfaces URGENT items, neglected projects, stuck
in-flight work, column load, and hygiene notes.

```bash
python3 scripts/forge-brief.py
python3 scripts/forge-brief.py --stale-days 5 --show 8
python3 scripts/forge-brief.py --calendar-calendars "Work,Teaching"
```

With an empty `--calendar-calendars` (the default), all calendars returned by
`forge calendar` are included. Restrict titles with a comma-separated list when needed.

This is **not** a `forge` subcommand; it requires `forge` on your `$PATH`.

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

---
name: forge-board
description: Reusable skill for managing a Forge kanban board — reading, moving, tagging, briefs, URGENT triage, and stale remediation.
version: 1.0.0
---

# Forge Kanban Board Skill

Manage the Forge kanban board: read project state, move projects between
columns, manage meta and assignee tags, generate briefs, triage URGENT
items, remediate stale projects, and collaborate via `#Person` tags.

## Requirements

- `forge` CLI must be on `$PATH` (install via Forge.app → Preferences → Install CLI).
- Projects live in directories under `project_roots` from `config.yaml`.
- Board column state is backed by Finder tags on project directories.

## Board Overview

Forge kanban columns (from `config.yaml`):

| Column Name | Column Tag (Finder Tag) | Colour Code |
|-------------|------------------------|-------------|
| Plan | `Plan 📐` | 4 |
| Watch | `Watch 👁️` | 2 |
| Coding | `Coding 🤖` | 5 |
| Write | `Write ✒️` | 6 |
| Review | `Review 🖍️` | 7 |
| Shipped | `Shipped 🚀` | 3 |
| Paused | `Paused ⏸️` | 1 |

Meta tags (from `config.yaml`):

| Meta Tag | Description |
|----------|-------------|
| `URGENT ⚠️` | Flag a project as requiring immediate attention. |
| `Student 🎓` | Indicate a student project. |
| `Completed ✔️` | Applied automatically ~7 days after Shipped (`forge archive` / Refresh). |

Kanban flow: `Plan → Watch → Coding → Write → Review → Shipped`
Side-column: All active columns can move to/from Paused.

## Procedures

### Reading the Board

1. `forge board` — Full board with projects grouped by column.
2. `forge board --list` — Compact single-column list.
3. `forge board -c <Column>` — Filter to a specific column.
4. `forge board -a <Person>` — Filter by assignee.
5. `forge board --json` — Full JSON with metadata (columns, meta_tags, radar, daysSinceActivity, activitySource). **Use this for structured analysis.**
6. `forge status` — Color-coded summary dashboard (column counts, total projects, active count, URGENT count).
7. `forge reminders` / `status` / `show` / `refresh` / `doctor` / `align` — optional Apple Reminders task backend (requires `reminders.enabled`). IDs are EventKit identifiers. `refresh` writes the snapshot, paints list colours, and sets URGENT sentinel priority; create lists with `align --apply`. `forge board --json` may include a `reminders` object per folder.

### Board Structure

When running `forge board --json`, the output includes:

```json
{
  "columns": [
    { "name": "Plan", "tag": "Plan \U0001F4D0" },
    { "name": "Watch", "tag": "Watch \U0001F441\UFE0F" },
    ...
  ],
  "meta_tags": ["URGENT \u26A0\uFE0F", "Student \U0001F393"],
  "projects": [
    {
      "name": "my-project",
      "path": "/path/to/my-project",
      "column": "Watch",
      "workflowTag": "Watch \U0001F441\UFE0F",
      "tags": ["URGENT \u26A0\uFE0F"],
      "metaTags": ["URGENT \u26A0\uFE0F"],
      "assignees": ["#Halfan"],
      "tags": [...],
      "radarBucket": "watch",
      "daysSinceActivity": 3,
      "activityModificationDate": "2026-05-01T...",
      "activitySource": "git"
    }
  ]
}
```

Extract `metaTags` for meta-tags only, `assignees` for `#Person` tags.
Column and workflowTag are always in sync (Forge ensures this).

### Moving a Project

Change a project's kanban column with `forge move`:

```bash
forge move <Project> <ColumnName>
```

- `<Project>` = directory name or unique substring.
- `<ColumnName>` = one of: Plan, Watch, Coding, Write, Review, Shipped, Paused.

Both arguments support prefix matching (e.g., `act` matches `Active`, `man` matches `manuscript`).

**CRITICAL: Always get user approval before executing `forge move`.**

### Task Tagging

Add, remove, or inspect meta and assignee Finder tags:

```bash
# List tags on a project
forge project-tag list <Project>
forge project-tag list <Project> --json

# Add a tag (meta or assignee)
forge project-tag add <Project> "URGENT \u26A0\uFE0F"
forge project-tag add <Project> "#Halfan"

# Remove a tag
forge project-tag remove <Project> "URGENT \u26A0\uFE0F"
```

- Without `--force`, `add`/`remove` only accept meta tags from `config.yaml` or `#Person` assignees.
- With `--force`, non-conforming tags are allowed (use sparingly).
- Workflow column tags are always rejected by `forge project-tag`; use `forge move` instead.

### Briefs

Morning review (when the user agrees) follows Forge `.cursor/rules/morning-brief.mdc`:

1. `forge omnifocus refresh --apply-finder` — sync OF snapshot + OF→Finder (orchestrator).
2. Parallelise calendar / OF today / board / GitHub as Hephaestus judges best
   (this pane for fast CLI; Herdr helpers with a suitable `--kind` only when faster).
3. Cap helper waits; take over locally on stall. Synthesise `## Brief` / `## Details`;
   no column/tag writes without approval.
4. Fallback: run all steps in this session if Herdr is unavailable.

Board-only brief generator:

```bash
python3 scripts/forge-brief.py
```

The board brief includes:

1. **Calendar** — today's events, upcoming events, warnings (events due within N hours).
2. **Column load** — project count per column.
3. **URGENT** — projects tagged `URGENT ⚠️`, sorted by staleness.
4. **Neglected** — projects ≥7 days inactive (across all columns).
5. **Stuck in-flight** — projects ≥14 days in Watch/Coding/Write/Review.
6. **Hygiene** — projects missing a column or workflow tag.

Common variants:
- `--stale-days 5` — catch stale earlier.
- `--show 8` — fewer lines per section.
- `--overdue-active-days 10` — flag stuck work sooner.
- `--calendar-timeout-seconds 30` — slower Calendar queries.

### URGENT Triaging

Workflow for URGENT projects:

1. **Surface**: `forge board --json | grep URGENT` or `forge-brief.py` URGENT section.
2. **Assess**: For each URGENT project, note column, daysSinceActivity, radarBucket, assignees.
3. **Identify next action**: Determine what the very next step is.
4. **Propose changes**: Move the project to the right column. Assign a `#Person` if needed. Propose to the user.
5. **Resolve**: After approval, `forge project-tag remove <Project> "URGENT ⚠️"`.
   When Reminders is enabled, adding or removing URGENT also sets high / none
   priority on that list’s sentinel (EventKit has no Flagged API).
6. **Escalate if needed**: If no progress after 14 days, note it as potentially stuck.

### Stale Remediation

Workflow for stale projects:

1. **Identify stale**: `forge-brief.py` shows Neglected (≥7 days) and Stuck in-flight (≥14 days in Watch/Coding/Write/Review).
2. **Assess each stale project**:
   - What column is it in?
   - What is the last activity and when?
   - Who is the assignee?
   - Is the project still relevant?
3. **Decide on remediation**:
   - Move to Paused if done or abandoned.
   - Move forward one column if ready.
   - Move back to Plan for re-planning.
   - Add `#Person` for delegation.
   - Mark as URGENT if critical.
4. **Propose to the user**: Present options and wait for approval.

### Calendar Integration

Read upcoming events:

```bash
forge calendar                      # Next 7 days
forge calendar --days 14            # Next 14 days
forge events                        # Alias for calendar
forge calendar --json               # Structured JSON
```

Calendar events are read-only. Forge uses Apple's EventKit. Configure
which calendars to read via `calendar.include` in `config.yaml`.

## Pitfalls

- **Never hardcode column names**: always validate against `config.yaml` or `forge board --json`.
- **Never use `forge project-tag` for column changes**: use `forge move`. `forge project-tag` rejects workflow column tags.
- **Never invent task IDs**: `<!-- id:... -->` is Forge-assigned. Leave IDs blank for new tasks.
- **Never mark URGENT**: always get user approval before adding `URGENT ⚠️`.
- **Never assume a project transition**: always propose and wait for approval.
- **Always read before writing**: run `forge board` or `forge board --json` before making any changes.
- **Stale remediation is advisory**: present options; do not automatically move projects.

## Command Reference

| Command | Purpose | Safe? |
|---------|---------|-------|
| `forge board` | View board | Yes |
| `forge board --json` | Full board JSON | Yes |
| `forge board -c <Col>` | Filter by column | Yes |
| `forge board -a <Person>` | Filter by assignee | Yes |
| `forge board --list` | Compact list | Yes |
| `forge status` | Summary dashboard | Yes |
| `forge move <Proj> <Col>` | Change column | No (approval required) |
| `forge project-tag list <Proj>` | Show tags | Yes |
| `forge project-tag add <Proj> <Tag>` | Add tag | No (approval required) |
| `forge project-tag remove <Proj> <Tag>` | Remove tag | No (approval required) |
| `forge calendar` | Read events | Yes |
| `forge events` | Alias | Yes |
| `forge --json` | Calendar JSON | Yes |
| `forge events --json` | Calendar JSON | Yes |
| `forge project-tag add <Project> "URGENT"` | Add URGENT flag | No |
| `forge project-tag remove <Project> "URGENT"` | Remove URGENT flag | No |
| `forge calendar --json` | Calendar JSON | Yes |

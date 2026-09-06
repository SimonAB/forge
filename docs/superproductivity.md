# Super Productivity

Forge is the project kanban **nexus** ([nexus.md](nexus.md)). When
`superproductivity.enabled` is true, **Super Productivity is the sole task
store**. Forge owns portfolio columns (sidecar + Finder / `user.xdg.tags`); SP
owns inbox, dues, capture, completion, focus, and time tracking.

## Current behaviour

| Concern | Behaviour when SP enabled |
|---------|---------------------------|
| `forge capture` / `forge tasks` | SP Inbox (`INBOX_PROJECT`); assign moves a task onto a mapped SP project |
| `forge-brief.py` inbox + dues | Live SP REST (`GET /tasks`), not `.forge/tasks.db` |
| Morning pull | OF Refresh for kanban join; drains Reminders **Inbox** → SP (`reminders-capture-drain.sh`); skips OF → `TASKS.toml` |
| `forge move` / board drag | Optional `nexus.sp_column_mirror`: Finder-style tags (e.g. `Coding 🤖`) on SP tasks |
| **Open TASKS** (board) | Opens / focuses the mapped SP project (Preferences → General) |
| `TASKS.toml` / `.forge/tasks.db` | Left on disk; **not** authoritative; not written by capture when SP is on |
| OmniFocus task import | Skips folders listed in `superproductivity.project_ids` |

When `superproductivity.enabled` is false, capture and briefs fall back to the
legacy task index (`.forge/tasks.db` / `TASKS.toml`).

## Setup

1. Install the stable desktop app (validated against 18.x local REST).
2. Enable **Settings → Misc → Local REST API** (`http://127.0.0.1:3876`).
3. Store the token (never put it in `config.yaml` or shell history):

```sh
python3 scripts/forge-superproductivity.py --forge-home . setup-token
# or: forge superproductivity setup-token
```

4. Ensure every Forge board folder has an SP project with the **exact** folder
   title, then map ids under `superproductivity.project_ids`.

```yaml
superproductivity:
  enabled: true
  endpoint: http://127.0.0.1:3876
  timeout: 5
  project_ids:
    Forge: "…"
    CausalDynamics.jl: "…"
```

### Open TASKS (board → SP project)

Forge.app **Open TASKS** (board card **tick** icon, context menu, or dashboard
project click) opens the preferred task manager. Preference:
**Forge → Preferences… → General → Open TASKS opens** (UserDefaults; Auto by
default).

| Preference | Behaviour |
|------------|-----------|
| Auto | SP if enabled → Reminders if enabled → OmniFocus if enabled → `TASKS.toml` |
| Super Productivity | Focus mapped project in SP (see below) |
| OmniFocus / Reminders | Activate that app |
| TASKS.toml (editor) | Open `<project>/TASKS.toml` in the preferred editor |

With Super Productivity selected (or Auto while `superproductivity.enabled`),
Forge focuses `#/project/<id>/tasks` via `scripts/forge-sp-focus-project.py`
(Chrome DevTools Protocol). That needs a `project_ids` entry for the folder.

```sh
# Manual focus (same helper the app uses)
/tmp/sp-cdp-venv/bin/python scripts/forge-sp-focus-project.py '<sp-project-id>'
```

The first focus in a session may briefly relaunch SP with
`--remote-debugging-port=9222` if CDP is not already available; later focuses
reuse that session. SP has no public URL scheme for opening an existing project.

See [app.md](app.md).

### Creating SP projects (Local REST cannot)

Local REST exposes `GET /projects` only. `POST /projects` returns **404**.
Create projects:

- **In the app** (exact folder titles), or
- **Plugin API** `addProject` (e.g. one-shot Forge plugin below).

Bulk helper (rebuilds the missing-title list from the live board):

```sh
python3 scripts/sp-plugins/build_forge_bulk_projects.py
# Upload scripts/sp-plugins/forge-bulk-projects.zip
#   Super Productivity → Settings → Plugins → Upload Plugin → enable
```

See [sp-plugins/README.md](../scripts/sp-plugins/README.md). After projects
exist, copy ids into `project_ids` (or re-run a title→id match against
`forge superproductivity list`).

Do **not** use a full SP backup JSON to invent projects unless you intend a
**full replace** of SP state.

### Project folders (sidebar hierarchy)

Local REST has no folder API. SP nests projects in `menuTree.projectTree`.
Nesting simply mirrors Finder paths under `~/Documents` (e.g.
`Work/Projects/Apodemus/…`). Re-apply after you rearrange folders:

```sh
# Preview
forge superproductivity mirror-menu-tree --dry-run
# or: python3 scripts/forge-sp-menu-tree.py --forge-home . --dry-run

# Apply (relaunches SP briefly with CDP; needs websocket-client)
python3 -m venv /tmp/sp-cdp-venv && /tmp/sp-cdp-venv/bin/pip -q install websocket-client
/tmp/sp-cdp-venv/bin/python scripts/forge-sp-menu-tree.py --forge-home .
# or: forge superproductivity mirror-menu-tree
```

Then quit and reopen Super Productivity normally. `project_ids` still match on
**folder name**, not path.

## Capture, assign, briefs

```sh
forge capture "Reply to Rivka" --source assistant   # → SP Inbox
forge tasks inbox
forge tasks assign <sp-id> "Forge"                  # requires project_ids entry
forge tasks complete <sp-id>
python3 scripts/forge-brief.py --calendar-days 1    # inbox + dues from SP
```

`forge tasks assign` fails clearly if the folder has no `project_ids` entry.
Notes may carry `[forge:source:…]` and a URI line for `forge tasks open`.

### Apple Reminders Inbox → SP Inbox

Super Productivity does not watch Apple Reminders. To approximate OmniFocus’s
Reminders capture, drain the Reminders list **`Inbox`** into SP with:

```sh
bash scripts/reminders-capture-drain.sh              # capture + mark completed
bash scripts/reminders-capture-drain.sh --dry-run    # JSON preview only
```

Each incomplete item becomes `forge capture … --source reminders` (SP Inbox).
On success the reminder is marked completed so the next run does not duplicate
it. Single-line URI notes are passed as `--link`; other notes as `--note`.
Stdout is a JSON summary (`scanned` / `captured` / `completed` / `failed`).

`bash scripts/morning-review-pull.sh` runs this drain automatically when
`superproductivity.enabled` is true (before `forge-brief.py`), soft-failing if
SP is down. A Shortcuts automation can also **Run Shell Script** with the
absolute path (schedule or menu bar). SP must be running (Local REST). This path
is independent of Forge’s project-list Reminders bridge (`forge reminders`).

## Column mirror

With `nexus.sp_column_mirror: true`, `forge move` and board drag paint
Finder-style column tags onto open tasks in the mapped SP project. Create those
tags in SP first (same strings as `board.columns[].tag`); REST cannot create
tags. CLI mirror:

```sh
python3 scripts/forge-superproductivity.py --forge-home . mirror-column Forge Coding \
  --tag "Coding 🤖" --kanban-tag "Watch 👁️" --kanban-tag "Plan 📐" # …
```

## Optional legacy TOML bridge

Mapped pilots can still three-way sync against `TASKS.toml` for migration:

```sh
python3 scripts/forge-superproductivity.py --forge-home . --json status
python3 scripts/forge-superproductivity.py --forge-home . --json doctor
python3 scripts/forge-superproductivity.py --forge-home . --json sync --apply Forge
```

Durations are milliseconds in SP and whole minutes in `TASKS.toml`. Date-only
deadlines use `dueDay`; timed deadlines use `dueWithTime`; planned dates use
`plannedAt`. Sync never auto-deletes. Prefer **one task backend per project**.

## Planned (not yet shipped)

Agreed direction; do not assume these exist until implemented:

1. **Retire day-to-day `TASKS.toml` use** — stop recommending ingest/due for active
   work; leave existing files on disk until explicitly deleted.
2. **Soft-deprecate** `forge-tasks-world.py` due/ingest paths when SP is enabled
   (or thin shims that read SP).
3. **Dashboard due strip** — ensure `forge-dashboard.py` / `forge dashboard`
   prefer SP dues the same way `forge-brief.py` does (brief already does).
4. **No mass-delete** of `TASKS.toml` without an explicit request.

## Safety notes

- Token: macOS Keychain service `forge-superproductivity`; Linux `secret-tool` or
  `~/.config/forge/superproductivity.token`.
- Loopback-only endpoint; redirects refused; failures redacted.
- SP must be running for capture and SP-backed briefs.
- SP supports only one-level subtasks.
- Rotate the API token if it was ever pasted into chat or logs.

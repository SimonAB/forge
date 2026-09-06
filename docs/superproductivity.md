# Super Productivity

Forge is the project kanban **nexus** ([nexus.md](nexus.md)). When
`superproductivity.enabled` is true, **Super Productivity is the sole task
store**. Forge owns portfolio columns (sidecar + Finder / `user.xdg.tags`); SP
owns inbox, dues, capture, completion, focus, and time tracking.

## Current behaviour

| Concern | Behaviour when SP enabled |
|---------|---------------------------|
| `forge capture` / `forge tasks` | SP Inbox (`INBOX_PROJECT`); assign moves a task onto a mapped SP project |
| Brief and dashboard inbox + dues | Live SP REST, including Inbox deadlines; dashboard joins mapped project IDs to board columns |
| Morning pull | OF Refresh (kanban); Reminders Inbox→SP drain; `mirror-board` when `sp_column_mirror`; skips OF→`TASKS.toml` |
| `superproductivity.primary` | OF frozen for day-to-day tasks; OF kept for column join + rollback ([of-frozen-sp-primary.md](of-frozen-sp-primary.md)) |
| `forge move` / board drag | Optional `nexus.sp_column_mirror`: Finder-style tags (e.g. `Coding 🤖`) on SP tasks |

| **Open TASKS** (board) | Opens / focuses the mapped SP project (Preferences → General) |
| `TASKS.toml` / `.forge/tasks.db` | Left on disk; **not** authoritative; not written by capture when SP is on |
| OmniFocus task import | Skips folders listed in `superproductivity.project_ids` |

When `superproductivity.enabled` is false, capture and briefs fall back to the
legacy task index (`.forge/tasks.db` / `TASKS.toml`).

## Setup

Install the Python helpers once from Forge's directory (Python 3.11 or later):

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r scripts/requirements.txt
source .venv/bin/activate
```

The CLI and app prefer this persistent environment for capture, dashboard, and
SP helpers. Morning pull also uses it. Direct Python commands below assume the
environment is activated. Configuration uses PyYAML's safe loader; `enabled`
must be a YAML boolean. Quoted project names and inline comments are supported.

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
.venv/bin/python scripts/forge-sp-focus-project.py '<sp-project-id>'
```

The first focus in a session may relaunch SP with `--remote-debugging-port=9222`
if CDP is unavailable; later focuses reuse that session. Forge requests a graceful
quit and waits for exit. If SP does not exit within the bounded wait, opening
fails without force-killing the app. Dependencies are checked before quitting.

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
python3 -m venv .venv && .venv/bin/python -m pip install -r scripts/requirements.txt
.venv/bin/python scripts/forge-sp-menu-tree.py --forge-home .
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
Notes may carry `[forge:source:…]`. Super Productivity blocks the `message://`
scheme ("Link blocked: unsafe URL scheme"), so Mail captures store only:

- `<!-- forge:uri:message://… -->` for the **Forge Mail Open** plugin and
  `forge tasks open`
- optionally a sidecar HTML under `.forge/mail-open/` for tooling (never linked
  from notes — `.html` opens in the default browser)

Install the plugin (header button **Open in Mail** on the selected task). Allow
**Node execution** when SP prompts — it opens the Mail **message object** by
Message-Id (no `message://` / no HTML). Without Node consent the button errors.

```sh
python3 scripts/sp-plugins/build_forge_mail_open.py
# Upload scripts/sp-plugins/forge-mail-open.zip in SP → Settings → Plugins
```

Ordinary `https://` links remain `[host](https://…)`.
### Context capture (Services + CLI)

Forge.app ships a macOS Service **Capture to Forge Inbox** that resolves by
context: Finder files → Mail selection (`message://`) → browser tab URL
(Safari / Chrome family) → selected text. Selected text is stored as a **note**
when a richer primary exists. **Capture Mail Message to Forge** is the same
engine with `--prefer mail` (for old shortcuts).

Portable CLI (works on Linux without Mail/browser frontmost detection):

```sh
python3 scripts/forge-capture.py service --prefer auto --file ~/doc.pdf
python3 scripts/forge-capture.py service --prefer auto --text "https://example.com"
```

See [app.md](app.md) and [omarchy.md](omarchy.md).

### OmniFocus → Super Productivity (one-shot)

Pending OmniFocus tasks can be copied into SP with:

```sh
python3 scripts/of-to-sp.py --write-plugin   # dry-run + of-bulk-projects.zip
# Upload scripts/sp-plugins/of-bulk-projects.zip in SP → Settings → Plugins
python3 scripts/of-to-sp.py                  # confirm blocked → create
python3 scripts/of-to-sp.py --apply          # create tasks (idempotent via [forge:of-id:…])
```

While `superproductivity.primary` is true, `--apply` is refused unless you pass
`--allow-while-primary` (dogfood: do not re-import on a schedule). See
[of-frozen-sp-primary.md](of-frozen-sp-primary.md).

| Source | Destination |
|--------|-------------|
| Forge-linked / aliased folder with an SP project | That mapped SP project |
| OF project or Single Action List with no SP project yet | **New** SP project titled as in OmniFocus (plugin creates it) |
| True Inbox (no containing project) | SP Inbox |

Local REST cannot create projects; the generated plugin uses `PluginAPI.addProject`.
Re-runs skip tasks already marked `[forge:of-id:<omnifocus-id>]` in SP notes.

### OmniFocus recurrence → SP repeat configs

Imported pending tasks do **not** keep OmniFocus repetition via Local REST
(upstream limitation). After import, attach SP `taskRepeatCfg` schedules from
OF RRULEs with:

```sh
python3 scripts/of-to-sp-repeats.py          # dry-run
.venv/bin/python scripts/of-to-sp-repeats.py --apply   # CDP write + reload
```

This writes IndexedDB `state_cache` (same technique as menu-tree mirror). Series
with multiple OF instances (e.g. deferred copies) collapse to one SP repeat
config. Complex RRULEs are approximated; check warnings in the dry-run.

### Eisenhower tags from OF flags / Forge URGENT

```sh
python3 scripts/of-eisenhower-tags.py          # dry-run
python3 scripts/of-eisenhower-tags.py --apply  # write SP tagIds
```

Maps OmniFocus **flagged** pending tasks → SP tag `important` (`EM_IMPORTANT`),
and open tasks in Forge **URGENT ⚠️** projects → SP tag `urgent` (`EM_URGENT`).

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

The drain keeps `.forge/reminders-capture-receipts.json` and a process lock.
After a confirmed capture, retries complete the original reminder using the
saved SP ID instead of creating another task. This also applies to
`--no-complete`. Dry runs write no receipts.

A pending receipt (`sp_id: null`) means capture was interrupted or could not be
confirmed. The drain leaves the reminder incomplete and refuses to recapture it.
To reconcile, stop drain automations, inspect SP, and either enter the existing
task's actual ID in that receipt or remove the receipt only after confirming
that capture did not create a task. Receipts are local and excluded from git;
they coordinate drains on this machine, not on multiple machines.

`bash scripts/morning-review-pull.sh` runs this drain automatically when
`superproductivity.enabled` is true (before `forge-brief.py`), soft-failing if
SP is down. A Shortcuts automation can also **Run Shell Script** with the
absolute path (schedule or menu bar). SP must be running (Local REST). This path
is independent of Forge’s project-list Reminders bridge (`forge reminders`).

## Column mirror

With `nexus.sp_column_mirror: true`, `forge move` and board drag paint
Finder-style column tags onto open tasks in the mapped SP project. The morning
pull also runs a full-board reconcile (`mirror-board`) so overnight drift is
corrected before `forge-brief.py`. Create those tags in SP first (same strings
as `board.columns[].tag`); REST cannot create tags.

```sh
# One project
python3 scripts/forge-superproductivity.py --forge-home . mirror-column Forge Coding \
  --tag "Coding 🤖" --kanban-tag "Watch 👁️" --kanban-tag "Plan 📐" # …

# All mapped board projects (respects nexus.sp_column_mirror; --force to override)
python3 scripts/forge-superproductivity.py --forge-home . --json mirror-board
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
3. **No mass-delete** of `TASKS.toml` without an explicit request.

## Safety notes

- Token: macOS Keychain service `forge-superproductivity`; Linux `secret-tool` or
  `~/.config/forge/superproductivity.token`.
- Loopback-only endpoint; redirects refused; failures redacted.
- SP must be running for capture and SP-backed briefs.
- SP supports only one-level subtasks.
- Rotate the API token if it was ever pasted into chat or logs.

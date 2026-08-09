# Reminders (optional)

Forge tracks **projects** with Finder-tag kanban. Day-to-day **tasks** can live in
OmniFocus, Apple Reminders, Things, or another app.

This page is the Reminders **task backend** (same role as OmniFocus): one EventKit
*list* per Forge project folder. Capture next actions in Reminders.app. Kanban
columns stay on Finder tags. List **colour** follows the Finder column. An optional
**sentinel** reminder can mirror the column if you turn on the sync flags.

Prefer one task app at a time. If OmniFocus and Reminders are both on, Refresh
applies OmniFocus column pull first.

## Enable

Open **Forge → Preferences → Reminders**, or set `reminders.enabled: true` in
`config.yaml`.

The Reminders panel offers:

- **Enable Reminders integration** — writes `reminders.enabled`.
- **Column mirror: board moves → sentinel reminder** — writes `reminders.sync_on_move`.
- **Column mirror: sentinel → Finder tags on Refresh** — writes
  `reminders.sync_from_reminders` (single-column steps only).
- **Include completed reminders by default** — writes `reminders.include_completed`.
- **Inbox list** — optional extra list title (`reminders.list`, default `Forge`).
- Snapshot status (age, list count, incomplete count).
- **Refresh now** — same as board **Refresh**: snapshot, list colours from Finder
  columns, URGENT → sentinel priority, and sentinel → Finder when that toggle is
  on (does not create lists).

macOS will ask for Reminders access for Forge.app (and separately for your
terminal if you fetch live from the CLI). Data stays on your Mac.

Folder aliases (`reminders.folder_aliases`), `sentinel_prefix`, and `source`
stay in `config.yaml`.

## Link model

- A Reminders **list** matches a Forge folder when the titles are equal
  (case-insensitive). Substring matches do not count: `Lab` does not match
  `Lab-notebook`.
- Ordinary reminders on that list are the project’s next actions. Forge **reads**
  them; it does not create, complete, or delete them.
- Optional `reminders.folder_aliases` maps a list title to a folder name. The
  target folder must exist.
- `reminders.list` (default `Forge`, also read from legacy `gtd.reminders_list`)
  is an extra inbox list: shown, but not treated as a project unless a folder
  has that name. Align does not create the inbox list.
- EventKit has no list groups, sections, or list **icons**. In Reminders.app you
  may group project lists and set icons by hand.

## List colour

When Forge creates a list (`align --apply`), you `forge move` / drag a card,
or you **Refresh** (board, Preferences **Refresh now**, or `forge reminders refresh`)
while Reminders is enabled, the list’s colour is set from
`board.columns[].colour` (same Catppuccin indices as the Forge board). Forge
never infers a kanban column from a colour you changed in Reminders.app.
`forge reminders paint-colours --apply` is the same paint without a snapshot.

## URGENT → sentinel priority

Finder meta tag `URGENT ⚠️` sets **high priority** (`1`) on that list’s kanban
sentinel. Removing URGENT clears it (`0`). EventKit has no Flagged API; Reminders.app
shows this as the exclamation / high-priority mark, not the orange flag.

Forge does not create a sentinel only for URGENT. If the list has no sentinel yet,
enable column sync and `forge reminders align --apply`, or wait until `sync_on_move`
writes one. **Refresh** and `forge reminders paint-priorities --apply` update
existing sentinels. `forge project-tag add|remove` of URGENT updates the sentinel
when one exists.

## Sentinel column (optional)

When `sync_on_move` or `sync_from_reminders` is on, each matched list may carry
one sentinel reminder:

| Field | Value |
|-------|--------|
| Title | `{sentinel_prefix}{Column}` e.g. `Forge · Watch` |
| Notes | `forge-kanban: Watch` |

`reminders.sentinel_prefix` defaults to `"Forge · "` (middle dot U+00B7).
Ordinary reminder items are left unchanged.

| Direction | When |
|-----------|------|
| Finder → sentinel | `forge move` / board drag, if `sync_on_move` is on |
| Sentinel → Finder | Board **Refresh**, Preferences **Refresh now**, or `forge reminders refresh --apply-finder`, if `sync_from_reminders` is on |
| Finder → list colour / URGENT priority | Board **Refresh**, Preferences **Refresh now**, `forge reminders refresh`, move / drag, `project-tag` (URGENT) |

Pull applies only a single-column step (or Paused side-column). Doctor drift
(`forge_only` / ambiguous) skips sentinel / colour writes for that folder unless
you pass `forge move --force`.

When OmniFocus and Reminders column pull are both on, Refresh applies
**OmniFocus first**; Reminders sentinels skip folders OF already updated.

Doctor / align may **propose** Finder Shipped when a list has no incomplete
tasks left (except the sentinel). That proposal is never applied automatically.

## Snapshot

Forge.app refreshes `.cache/reminders-snapshot.json` in the background (snapshot
only; no colour or priority paint). Board **Refresh**, Preferences **Refresh now**,
and `forge reminders refresh` update the snapshot, paint list colours, and set
sentinel priority from Finder URGENT. They do not create lists. Create missing
lists with `forge reminders align --apply`. Unmatched personal lists are left
alone. Sentinels still follow the sync flags / `align --apply`.

`forge reminders` / `show` / `doctor` use a fresh snapshot when it is younger
than `reminders.snapshot_max_age_seconds` (default 900). Pass `--live` to force
EventKit and ignore the snapshot.

## Typical flow

```bash
forge reminders status
forge reminders refresh         # snapshot + list colours + URGENT priority
forge reminders                 # incomplete reminders, grouped by project
forge reminders doctor          # folders ↔ lists (read-only)
forge reminders align           # dry-run: create missing lists / sentinels
forge reminders align --apply   # confirm, then write
forge reminders paint-colours --apply      # colours only (no snapshot)
forge reminders paint-priorities --apply   # URGENT priority only
forge reminders refresh --apply-finder   # also sentinel → Finder, if sync_from_reminders
```

`forge board --json` includes a `reminders` object per matched folder when
Reminders is enabled and the snapshot is eligible: `incompleteCount`,
`nextReminder`, `due`, `snapshotAgeSeconds`.

## Config keys

| Key | Meaning |
|-----|---------|
| `reminders.enabled` | Gate for CLI list/show/refresh/doctor/align (status still runs) |
| `reminders.list` | Optional inbox list title (default `Forge`) |
| `reminders.include_completed` | Default listing includes completed items |
| `reminders.snapshot_max_age_seconds` | Snapshot freshness window (default 900) |
| `reminders.sync_on_move` | Finder column → sentinel after `forge move` / board drag (default false) |
| `reminders.sync_from_reminders` | Sentinel → Finder on Refresh / `--apply-finder` (default false) |
| `reminders.sentinel_prefix` | Sentinel title prefix (default `"Forge · "`) |
| `reminders.source` | EventKit account title when creating lists (optional) |
| `reminders.folder_aliases` | List title → Forge folder name |

See [config.sample.yaml](../config.sample.yaml).

## Further reading

- [CLI `forge reminders`](cli.md#forge-reminders)
- [Forge.app — Reminders](app.md#reminders-optional)
- [OmniFocus bridge](omnifocus.md)
- [Privacy](../PRIVACY.md)

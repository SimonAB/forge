# Forge as nexus

Forge is the **project kanban nexus**: one column (and meta/assignee tags) per
project folder. Portable state travels with the folder; each OS paints native
attributes locally. OmniFocus and Super Productivity are **subordinate** joins,
not competing boards of record.

## Authority

| Layer | Role |
|-------|------|
| `<project>/.forge/kanban.toml` | Portable canonical column + meta + assignees (git / Dropbox / LocalSend) |
| Finder tags (macOS) | Local projection |
| `user.xdg.tags` (Linux) | Local projection (same tag strings as `config.yaml`) |
| OmniFocus | macOS column mirror on linked tasks (`sync_on_move` / Refresh pull) |
| Super Productivity | Sole task store when enabled; optional Finder-style column tag mirror |

## Sidecar schema (v1)

```toml
schema = 1
column = "Coding"
workflow_tag = "Coding 🤖"
meta = ["URGENT ⚠️"]
assignees = ["#Alice"]
updated_at = "2026-09-06T10:00:00Z"
source = "forge-move"
```

`source` is one of: `forge-move`, `project-tag`, `fs-import`, `of-refresh`, `migrate`, `fs-sync`.

## Write path

`forge move` and board drag go through **KanbanNexus**: when `nexus.sidecar_enabled`
is true, Forge writes the sidecar and local tags together, then runs OF / Reminders /
optional SP column mirror hooks.

## After sharing folders

Dropbox, git, and LocalSend do **not** translate Finder tags ↔ Linux xattrs.
After sync settles:

```bash
forge fs doctor          # sidecar ↔ tags drift
forge fs sync --apply    # paint local tags from sidecar (default)
forge fs sync --prefer finder --apply   # promote local tags into sidecar
forge fs migrate         # bootstrap sidecars from current tags (dry-run default)
```

## Refresh order (when sidecar sync on refresh is on)

1. Sidecar → local tags (`forge fs` paint)
2. OmniFocus → Finder (existing)
3. Reminders (existing; skips folders OF already updated)

## Dual OS

- **macOS:** Forge.app + CLI; Finder tags; optional OF / Reminders.
- **Omarchy / Linux:** CLI (`forge board`, `forge move`, `forge fs`, dashboard script);
  `user.xdg.tags`; SP via local REST. No OmniFocus/Reminders.

Enable in `config.yaml`:

```yaml
nexus:
  sidecar_enabled: true
  prefer_sidecar: true
  sync_sidecar_on_refresh: true
  sp_column_mirror: false
```

## Task backends

With `superproductivity.enabled`, **Super Productivity is the sole task store**
(inbox, dues, capture, briefs). Forge stays the **kanban nexus**. Map folder
names to SP project ids in `config.yaml`. Local REST cannot create projects
(`POST /projects` → 404); create them in the app or via Plugin API
`addProject` (see [superproductivity.md](superproductivity.md) and
`scripts/sp-plugins/`). Optional `nexus.sp_column_mirror` paints Finder-style
column tags onto SP tasks on `forge move` / board drag.

Forge.app **Open TASKS** (board tick icon / context menu) opens the preferred
task manager and, for SP, focuses the mapped project
([app.md](app.md), [superproductivity.md](superproductivity.md)).

Legacy `TASKS.toml` / `.forge/tasks.db` remain on disk when SP is enabled but are
not authoritative. OmniFocus task import skips mapped SP projects. Full cutover
notes and planned retirement of the TOML path: [superproductivity.md](superproductivity.md).

## Visual board

macOS keeps Forge.app. On Linux use `forge board` / `python3 scripts/forge-dashboard.py`.
Do not treat SP’s task kanban as the portfolio board of record.

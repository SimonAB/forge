# OmniFocus (optional)

Forge is the project kanban **nexus** ([nexus.md](nexus.md)). When
`superproductivity.enabled` is true, **Super Productivity is the sole task
store** ([superproductivity.md](superproductivity.md)); OmniFocus remains a
**macOS-only** subordinate column join on linked tasks/projects. Otherwise
day-to-day tasks may live in OmniFocus, [Reminders](reminders.md), Things, or
another app.

This page is the OmniFocus bridge: it keeps *project* columns in step with
OmniFocus via Omni Automation (OmniJS). Mutating commands default to **dry-run**.
Apple Reminders is the other optional macOS task backend ([reminders.md](reminders.md)).
When `nexus.sync_sidecar_on_refresh` is on, Refresh paints sidecar → local tags
**before** OmniFocus → Finder. Mapped SP projects are skipped by the OmniFocus
→ `TASKS.toml` importer.

## Enable

Set `omnifocus.enabled: true` in `config.yaml`, or open
**Forge → Preferences → OmniFocus**.

Requires OmniFocus installed and Automation permission for your terminal and/or
Forge.app. Data stays on your Mac.

## Typical flow

```bash
forge omnifocus doctor              # check links and drift
forge omnifocus align               # dry-run plan
forge omnifocus align --apply       # write after confirmation
```

In the menu bar: **OmniFocus Align…** (preview, then Apply).

## Sync directions

| Direction | When |
|-----------|------|
| Finder → OmniFocus | `forge move` / board drag, if `sync_on_move` is on |
| OmniFocus → Finder | Board **Refresh**, or `forge omnifocus refresh --apply-finder`, if `sync_from_omnifocus` is on |
| Completed OF project → Shipped | Refresh, if `sync_completed_project_to_shipped` is on |
| Leave Shipped → reopen OF project | Board/`forge move`, if `reopen_of_project_when_leaving_shipped` (default true) and `sync_on_move` |
| Enter Shipped → OF project Done | Board/`forge move`, if `complete_of_project_when_entering_shipped` (default true) and `sync_on_move` |

Once a folder has been shipped (or you leave **Shipped** on the board / in Finder),
Refresh will **not** keep forcing Shipped on every sync. Move the folder back to
**Shipped** yourself to clear that override. Leaving Shipped also reopens the matching
OmniFocus project when the reopen flag is on, so OF status stays aligned with Finder.

Refresh does not push Finder columns onto OmniFocus. If doctor reports drift,
`sync_on_move` skips OF writes unless you allow sync with drift or pass
`forge move --force`. When Reminders column pull is also on, Refresh applies
OmniFocus first; Reminders sentinels skip folders OF already updated.

Link tags default to `🔥 Forge:<name>` (legacy `Forge:` still readable). Flat
column aliases such as `Watch 🚧` are preferred when `flat_column_tags` is true.

## Further reading

- [CLI `forge omnifocus`](cli.md#forge-omnifocus)
- [Forge.app — OmniFocus](app.md#omnifocus-optional)
- [Privacy](../PRIVACY.md)
- [Automation plug-in notes](packaging/omnifocus/README.md)

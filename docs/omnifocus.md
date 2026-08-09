# OmniFocus (optional)

Forge can optionally keep kanban columns in step with **OmniFocus** via Omni
Automation (OmniJS). Mutating commands default to **dry-run**; nothing is written
until you apply a plan.

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

Refresh does not push Finder columns onto OmniFocus. If doctor reports drift,
`sync_on_move` skips OF writes unless you allow sync with drift or pass
`forge move --force`.

Link tags default to `🔥 Forge:<name>` (legacy `Forge:` still readable). Flat
column aliases such as `Watch 🚧` are preferred when `flat_column_tags` is true.

## Further reading

- [CLI `forge omnifocus`](cli.md#forge-omnifocus)
- [Forge.app — OmniFocus](app.md#omnifocus-optional)
- [Privacy](../PRIVACY.md)
- [Automation plug-in notes](packaging/omnifocus/README.md)

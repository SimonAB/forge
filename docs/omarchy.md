# Omarchy / Linux board parity

Forge is the kanban **nexus** on both macOS and Omarchy ([nexus.md](nexus.md)).
This page is the Linux day-to-day view.

## CLI (required)

Build and install the `forge` executable (Swift toolchain on the Linux host).
OmniFocus, Reminders, Forge.app, and the menu bar are macOS-only; the CLI
commands below are the shared surface:

```bash
forge board
forge board --json
forge move <Project> <Column>
forge project-tag list|add|remove …
forge fs doctor
forge fs migrate          # dry-run
forge fs migrate --apply  # bootstrap .forge/kanban.toml from tags
forge fs sync --apply     # after Dropbox / git / LocalSend
forge status
```

Enable the sidecar in `config.yaml`:

```yaml
nexus:
  sidecar_enabled: true
  prefer_sidecar: true
  sync_sidecar_on_refresh: false   # no OF Refresh on Linux
  sp_column_mirror: false          # optional with Super Productivity
```

Local tags use `user.xdg.tags` (comma-separated), with the **same** strings as
`board.columns[].tag` / `meta_tags` in config.

## Dashboard (visual)

```bash
python3 scripts/forge-dashboard.py --layout compact
python3 scripts/forge-dashboard.py --layout split
python3 scripts/forge-dashboard.py --layout tick --watch 30
```

These read `forge board --json` and use the same column model as Forge.app.

## Super Productivity

Install the desktop app, enable local REST (`127.0.0.1:3876`), map
`superproductivity.project_ids`, and store the token with
`forge superproductivity setup-token` (Keychain on macOS; `secret-tool` or
`~/.config/forge/superproductivity.token` on Linux).

SP is the **task** plane. Do not use SP’s task kanban as the portfolio board of
record.

## Sharing folders

After syncing a project tree to the other OS:

```bash
forge fs sync --apply
```

Native Finder / xattr blobs do not travel across Dropbox/git/LocalSend; the
sidecar does.

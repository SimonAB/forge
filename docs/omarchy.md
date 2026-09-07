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

The native Linux board window is available from the source checkout:

```bash
scripts/linux/forge-board
```

It uses the Forge CLI as its data boundary, displays project cards by column,
opens a project in the default file manager, and reports Super Productivity
task/inbox counts. Linux calendar unavailability is shown in the status line;
the board does not attempt to emulate the university Office 365 web calendar.
The initial window is read-only for project state, so opening a card cannot
accidentally move a project or alter Finder-compatible tags.

For a desktop launcher, install the executable and desktop entry into the
user-local locations (no Omarchy system files are changed):

```bash
scripts/linux/install-forge-board
```

The launcher is also suitable for a user-owned Omarchy application menu. A
Quickshell bar widget can be added separately once the window's read-only
surface has settled.

## Omarchy bar widget

The source tree includes a user-installable Quickshell widget at
`packaging/omarchy/io.github.simonab.forge`. It runs `forge dashboard --json`,
shows column counts and SP inbox/open-task counts, and offers buttons for the
GTK board and SP. Install it by copying that directory to
`~/.config/omarchy/plugins/io.github.simonab.forge/`, then enable it and add
the widget to the bar:

```bash
omarchy plugin enable io.github.simonab.forge
omarchy bar put io.github.simonab.forge --section right
```

If `omarchy bar put` is unavailable in the installed Omarchy version, add
`{"id":"io.github.simonab.forge"}` to the desired section of
`~/.config/omarchy/shell.json`, then run `omarchy-shell shell reload`.
The plugin is deliberately kept out of the repository's live Omarchy config;
macOS menu-bar behaviour and each machine's Linux layout remain independent.

## Super Productivity

SP is the **task** plane when `superproductivity.enabled` is true (capture,
inbox, dues, briefs). Install the desktop app, enable local REST
(`127.0.0.1:3876`), create projects with **exact** Forge folder titles (in-app
or Plugin API — Local REST cannot create projects), map
`superproductivity.project_ids`, and store the token with
`forge superproductivity setup-token` (`secret-tool` or
`~/.config/forge/superproductivity.token` on Linux).

Capture on Linux (no macOS Services / Mail.app):

```bash
forge capture "Reply to Rivka" --source cli
python3 scripts/forge-capture.py service --file ~/notes.pdf --text "page 3"
python3 scripts/forge-capture.py service --text "https://example.com/doc"
```

`--prefer auto` skips Mail/browser frontmost detection off macOS; use explicit
`--file` / `--text` / `forge capture --link`. See [app.md](app.md) Quick capture.

Do not use SP’s task kanban as the portfolio board of record. Details:
[superproductivity.md](superproductivity.md).

## Sharing folders

After syncing a project tree to the other OS:

```bash
forge fs sync --apply
```

Native Finder / xattr blobs do not travel across Dropbox/git/LocalSend; the
sidecar does.

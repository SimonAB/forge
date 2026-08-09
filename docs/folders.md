# Folders first

Projects are ordinary directories under your configured **project roots**.
Forge does not import them into a proprietary store.

## Project roots

Set `project_roots` in `config.yaml`. By default (`project_scan_depth: 1`) each
**direct child** folder is a project. Use `project_scan_depth: 2` when work lives
inside grouping folders (for example a manuscript inside a research programme
directory). Tagged folders are not scanned further.

If `project_tag` is set (for example `🔥 Forge`), only directories with that
Finder tag count as projects.

## Visible where you already look

- **Finder** and **Spotlight** see the same folders and tags.
- Keep the workspace under **git** if you want history; Forge does not require it.
- Place the tree on an encrypted volume or a local-only folder if you prefer not
  to sync via iCloud or similar.

See [configuration](../README.md#configuration),
[CLI project roots](cli.md#configuration-project-roots), and the
[manual](forge-manual.md#core-concepts).

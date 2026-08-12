# Kanban

Forge’s board is a **Finder-tag kanban**: each project folder carries one workflow
column tag. Moving a card updates that tag. Day-to-day tasks can live in
OmniFocus, Reminders, Things, or another app.

## Columns

Default flow (left to right):

| Column | Finder tag |
|--------|------------|
| Plan | Plan 📐 |
| Watch | Watch 👁️ |
| Coding | Coding 🤖 |
| Write | Write ✒️ |
| Review | Review 🖍️ |
| Shipped | Shipped 🚀 |
| Paused | Paused ⏸️ |

**Paused** is a side column: any active column except Shipped may pause.
A shipped project stays Shipped.

Change column with `forge move <project> <Column>` or by dragging a card in
Forge.app. Pass `--strict` on the CLI if you want one-column steps and the
Shipped/Paused rules enforced.

Column names and tags come from `board.columns` in `config.yaml`.

## Radar

The board **Radar** picker slices projects into three buckets without changing
tags or files:

- **Calm** — recently touched, non-urgent
- **Watch** — little recent activity (about a week)
- **Heat** — `URGENT` meta tags, or neglected for several weeks

Use it to surface work that is both time-sensitive and at risk of being
forgotten.

## Completed after Shipped

Projects that move to **Shipped** keep only the workflow tag at first. After
`board.archive_after_shipped_days` (default **7**), Forge adds the `Completed ✔️`
meta tag (must be listed under `board.meta_tags`).

- Ship date is stored in `.cache/shipped-at.json` when a folder enters Shipped.
- Board **Refresh** and `forge archive` apply due tags; `forge archive --dry-run`
  lists countdowns without writing.
- Shipped cards show a **complete in Nd** countdown until the tag is due.
- Existing Shipped folders without a cache entry use folder activity age; if
  already older than the delay, they are tagged on the next sweep.
- Legacy `Archived…` Finder tags on Shipped folders migrate to `Completed ✔️`.

## Where to look

- Terminal: [`forge board`](cli.md#forge-board) / `forge board --json`
- Forge.app: **Board** (Cmd+B)
- Longer tour: [user manual](forge-manual.md)

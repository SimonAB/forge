# Kanban

Forge’s board is a **Finder-tag kanban**: each project folder carries one workflow
column tag. Moving a card updates that tag. There is no separate board database.

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

## Where to look

- Terminal: [`forge board`](cli.md#forge-board) / `forge board --json`
- Forge.app: **Board** (Cmd+B)
- Longer tour: [user manual](forge-manual.md)

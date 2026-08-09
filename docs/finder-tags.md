# Finder tags

Kanban state and project metadata live in **Finder tags** on the project folder —
not in a hosted database.

## Workflow columns

Each project has one column tag, from `board.columns` in `config.yaml`. Change it
only with [`forge move`](cli.md#forge-move) or a board drag.
[`forge project-tag`](cli.md#forge-project-tag) refuses workflow tags so column
state stays consistent.

## Meta tags and assignees

Configured **meta** tags (for example `URGENT ⚠️`, `Collab 🤝`, `Student 🎓`) and
`#Person` assignees are added or removed with `forge project-tag`.

The board can filter by assignee; the CLI accepts `forge board -a #Name`.

## Visible outside Forge

Tags show in Finder (Get Info, tag column) and are searchable in Spotlight.
People-tags such as `#Alice` remain meaningful when Forge is not running.

See the [manual](forge-manual.md#delegated-work-and-assignees) and
[CLI `forge project-tag`](cli.md#forge-project-tag).

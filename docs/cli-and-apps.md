# CLI & apps

Forge is three surfaces on the same on-disk model: ordinary folders and Finder
tags. Pick the surface that fits the moment.

## `forge` CLI

Boards, column moves, meta/assignee tags, read-only Calendar, and optional
OmniFocus / Reminders bridges.

```bash
forge board
forge board --json
forge move <project> <Column>
forge status
forge reminders status
forge reminders doctor
forge reminders refresh
```

Full reference: [CLI](cli.md).

## Forge.app

Menu bar companion, native board window, Preferences (Brief, Hermes, OmniFocus,
Reminders), and Sparkle updates. Install the CLI onto your `$PATH` from
**Forge → Preferences… → Install CLI…**.

Guide: [Forge.app](app.md).

## Neovim

Keymaps, commands, and dashboard integration via `forge-nvim.lua`.

Guide: [Neovim](neovim.md).

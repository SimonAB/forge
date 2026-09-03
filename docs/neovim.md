# Forge — Neovim integration

Forge is folder-first **project** kanban. Day-to-day tasks can live in OmniFocus,
Reminders, Things, or similar. Keep Neovim integration on kanban and Finder-tag
commands.

**File:** `~/.config/nvim/lua/plugins/forge-nvim.lua`

## Finder “Open With” (NeoVim launcher)

macOS **NeoVim launcher.app** (Automator) can open dropped files or folders via:

```bash
forge edit [paths…]
```

That uses the same terminal path as Forge board “open in Vim”: when `terminal:` is
`auto` (or `herdr` / `tmux`), prefers a live Herdr or tmux session, otherwise
Ghostty / kitty / iTerm / Warp / Terminal. See [CLI — forge edit](cli.md#forge-edit).

Install the CLI from **Forge → Preferences… → Install CLI…** so the launcher can
resolve `~/bin/forge` (Automator’s `PATH` is thin).

## Dependencies

| Plugin | Role |
|--------|------|
| [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim) | Terminal panes for CLI output |
| [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) | Fuzzy file browsing and grep within your project roots |
| [which-key.nvim](https://github.com/folke/which-key.nvim) | Displays `<leader>F` group in the keymap popup |
| [mini.starter](https://github.com/echasnovski/mini.starter) | Dashboard section with Forge shortcuts |

All dependencies should be optional (`pcall`) so the plugin degrades gracefully.

## Suggested keymaps

All keymaps use the `<leader>F` prefix (normal mode).

### View commands

Read-only output in a terminal pane. Press `q` to close.

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>Fb` | `forge board --list` | Kanban board (list view) |
| `<leader>Ft` | `forge status` | Project summary dashboard |
| `<leader>Fc` | `forge calendar` | Upcoming Calendar events |

### Project maintenance

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>Fm` | `forge move` | Move a project to a column (interactive args in terminal) |
| `<leader>Ftg` | `forge project-tag` | Add/remove/list Finder tags on a project folder |

## Commands

If you expose Neovim commands, these cover the kanban-only surface area:

| Command | Description |
|---------|-------------|
| `:ForgeBoard` | Show kanban board |
| `:ForgeStatus` | Show project status dashboard |
| `:ForgeCalendar` | Show upcoming events |
| `:ForgeMove` | Move a project between columns |
| `:ForgeProjectTag` | Add/remove/list project tags |
| `:ForgeSetup` | Build and install Forge on this Mac (runs `build.sh`) |

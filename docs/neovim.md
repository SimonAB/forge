# Forge — Neovim integration

The `forge-nvim` plugin provides keymaps, commands, and dashboard shortcuts
for managing Forge directly from Neovim.

**File:** `~/.config/nvim/lua/plugins/forge-nvim.lua`

## Dependencies

| Plugin | Role |
|--------|------|
| [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim) | Terminal panes for CLI output and interactive commands |
| [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) | Fuzzy file browsing and grep within the Forge directory |
| [which-key.nvim](https://github.com/folke/which-key.nvim) | Displays `<leader>F` group in the keymap popup |
| [mini.starter](https://github.com/echasnovski/mini.starter) | Dashboard section with Forge shortcuts |

All dependencies are loaded via `pcall` — the plugin degrades gracefully if
any are missing.

---

## Auto-detection and setup

On load, the plugin checks whether the `forge` CLI is on `$PATH`:

- **Available** — all keymaps are registered.
- **Missing** — keymaps are skipped and a notification suggests running
  `:ForgeSetup`.

`:ForgeSetup` is always registered regardless, so you can bootstrap Forge on a
fresh Mac without leaving Neovim.

---

## Keymaps

All keymaps use the `<leader>F` prefix (normal mode). Press `<leader>F` to see
the full list via which-key.

### View commands

Read-only output in a horizontal terminal pane. Press `q` to close.

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>Fn` | `forge next` | Next actions across all projects |
| `<leader>Fb` | `forge board --list` | Kanban board (list view) |
| `<leader>Fp` | `forge projects` | Tasks per project |
| `<leader>Ft` | `forge status` | Project summary dashboard |
| `<leader>Fw` | `forge waiting` | All waiting-for items |
| `<leader>Fx` | `forge contexts` | Tasks grouped by context |
| `<leader>Fm` | `forge someday` | Someday / maybe list |
| `<leader>FD` | `forge due` | Overdue & due tasks |

### Interactive commands

Vertical terminal pane with insert mode for user input.

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>Fr` | `forge review` | Guided weekly review |
| `<leader>FI` | `forge process` | Triage inbox items into projects |

### Sync

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>Fs` | `forge sync --verbose` | Sync with Reminders & Calendar |

### Capture and complete

| Key | Description |
|-----|-------------|
| `<leader>Fc` | **Quick capture** — prompts for text, runs `forge inbox "<text>"` |
| `<leader>Fd` | **Complete task** — reads the task ID from the cursor line (`<!-- id:XXXXXX -->`), or prompts if none found. Reloads the buffer afterwards. |

### Focus sessions

| Key | Description |
|-----|-------------|
| `<leader>Ff` | **Set focus session** — pick from work / personal / spiritual / clear |
| `<leader>Fo` | Show current focus and available tags |

### File access and search

| Key | Description |
|-----|-------------|
| `<leader>Fi` | Open `inbox.md` |
| `<leader>Fa` | Telescope file picker scoped to `~/Documents/Forge` |
| `<leader>Fg` | Telescope live grep scoped to `~/Documents/Forge` |

---

## Commands

Available via the command line (`:ForgeXxx`) or from other plugins and scripts.

| Command | Arguments | Description |
|---------|-----------|-------------|
| `:ForgeNext` | — | Show next actions |
| `:ForgeBoard` | — | Show kanban board |
| `:ForgeProjects [name]` | Optional project name | Tasks per project; filters by name if given |
| `:ForgeSync` | — | Sync with Reminders & Calendar |
| `:ForgeReview` | — | Guided weekly review (interactive) |
| `:ForgeCapture [text]` | Optional task text | Capture to inbox; prompts if no text given |
| `:ForgeDone [id]` | Optional 6-char hex ID | Complete a task; auto-detects ID from cursor line |
| `:ForgeDue [days]` | Optional lookahead in days | Show overdue and due tasks (default: 7 days) |
| `:ForgeFocus [tag]` | Optional tag or `clear` | Set, show, or clear a focus session |
| `:ForgeSetup` | — | Build and install Forge on this Mac (runs `setup.sh`) |

---

## Dashboard

The [mini.starter](https://github.com/echasnovski/mini.starter) dashboard
includes a **Forge** section with four shortcuts:

| Key | Label | Action |
|-----|-------|--------|
| `I` | Inbox | Opens `~/Documents/Forge/inbox.md` |
| `N` | Next actions | Runs `:ForgeNext` |
| `B` | Board | Runs `:ForgeBoard` |
| `R` | Review | Runs `:ForgeReview` |

When the `forge` CLI is not installed but `setup.sh` exists, the section shows
a single **"Set up Forge"** item bound to `I`.

---

## Completing tasks from a markdown buffer

When editing a Forge markdown file, place your cursor on a task line and press
`<leader>Fd`. The plugin extracts the task ID from the `<!-- id:XXXXXX -->`
comment, runs `forge done XXXXXX`, and reloads the buffer so the checkbox
updates to `[x]`.

If no ID is found on the current line, you are prompted to enter one manually.

---

## Typical workflow

1. Open Neovim — the dashboard shows Forge shortcuts.
2. Press `I` to open your inbox and review captured items.
3. Press `<leader>Fp` to process inbox items into projects.
4. Press `<leader>Fn` to see your next actions.
5. Work on a task, then `<leader>Fd` on its line to mark it done.
6. Press `<leader>Fc` to capture a new thought without leaving your editor.
7. Press `<leader>Fs` to sync changes with Reminders and Calendar.
8. Press `<leader>Fr` at the end of the week for a guided review.

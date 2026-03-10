# Forge.app

Forge.app is a macOS **menu bar companion** that runs in the background,
providing quick capture, automatic sync, and at-a-glance status badges.

## Setup

Run the setup script on each Mac:

```bash
zsh ~/Documents/Forge/build.sh
```

This performs the following steps:

1. **Local build directory** — creates `~/.forge-build` outside iCloud Drive
   and symlinks it as `.build` in the source tree so compiled artefacts don't
   sync.
2. **Swift build** — compiles the CLI (`forge`) and menu bar app
   (`forge-menubar`).
3. **CLI symlink** — links `forge` into `/opt/homebrew/bin` (or
   `/usr/local/bin` / `~/.local/bin`).
4. **App bundle** — assembles `/Applications/Forge.app` with the compiled
   binary, an `Info.plist`, and an optional generated icon.
5. **Launch Agent** — installs
   `~/Library/LaunchAgents/com.forge.menubar.plist` so Forge.app starts
   automatically at login.
6. **Verification** — runs `forge --version` to confirm the install.

### Icon generation

The setup script calls `generate_icon.py` to create a themed app icon. This
requires Python 3 with [Pillow](https://pypi.org/project/Pillow/):

```bash
pip3 install Pillow
```

If Pillow is not installed, the icon step is skipped and a default icon is used.

### Launching from Spotlight

Forge.app is installed in `/Applications`, so it is discoverable via Spotlight
(Cmd+Space, type "Forge"). It appears in the Dock and in the application
switcher (Cmd+Tab), and also shows a menu bar icon.

---

## Menu bar icon

The status bar displays a hammer icon (SF Symbol `hammer.fill`). A badge
indicates urgent items:

| Badge | Meaning |
|-------|---------|
| Red number | Overdue tasks |
| Orange number | Tasks due today (no overdue) |
| No badge | Nothing urgent |

---

## Menu items

| Item | Shortcut | Description |
|------|----------|-------------|
| *X overdue* | — | Shown in red; **click** opens `forge due` in the terminal |
| *X due today* | — | Shown when tasks are due today; **click** opens `forge due` |
| *X in inbox* | — | Shown when inbox has pending items |
| **Quick Capture...** | Cmd+Shift+N | Opens a floating text field to capture a task to the inbox |
| **Sync Now** | Cmd+S | Triggers an immediate sync cycle |
| *Last sync: X ago* | — | Informational — shows time since last sync |
| **Board** | Cmd+B | Opens the native Kanban board window |
| **Open Board in Terminal** | — | Runs `forge board` in your terminal |
| **Weekly Review in Terminal** | Cmd+R | Runs `forge review` in your terminal |
| **Quit Forge** | Cmd+Q | Stops the sync timer and exits |

---

## Background sync

Forge.app runs a sync cycle automatically:

- **On launch** — immediate sync.
- **Every 5 minutes** — repeating timer.
- **On demand** — via the "Sync Now" menu item.

Each sync cycle performs **two-way synchronisation** between your markdown
files and Apple's Reminders and Calendar:

| Direction | What happens |
|-----------|--------------|
| Forge → Reminders | Tasks are created or updated in the configured Reminders list (or in a context list "Forge • &lt;context&gt;" when the task has an @ctx tag) |
| Forge → Calendar | Due dates are mirrored as all-day Calendar events |
| Reminders → Forge | New items added to the Reminders list are imported to `inbox.md` |
| Reminders → Forge | Completing a Reminder marks the corresponding Forge task as done |
| Forge → Reminders | Completing a Forge task marks the corresponding Reminder as complete |
| **Calendar → Markdown** | If you change an event's date in Calendar, the next sync updates the task's `@due(...)` in the markdown file |
| Forge → Finder | Area-level tags (e.g. `work`, `personal`) are applied as Finder tags on area `.md` files |

**Area tasks are included in sync.** Tasks from area files (admin.md,
home.md, etc.) are synced to Reminders and Calendar alongside project tasks.

### Tag propagation

Area tags from YAML frontmatter are surfaced across all sync targets:

| Surface | How tags appear |
|---------|-----------------|
| **Reminders** | Stored in the reminder's notes field (`tags: work, personal`) |
| **Calendar** | Prefixed in the event title (`[work] [Admin] Task name`) and in the event notes |
| **Finder** | Applied as Finder tags on the area `.md` files (visible in Finder, searchable via Spotlight) |
| **Forge files** | Stored in YAML frontmatter (`tags: [work]`) |

Project tasks inherit the `workspace_tags` from `config.yaml` (default: `[work]`).

### Badge counts

The overdue and due-today badge counts are calculated by **recursively
scanning all `TASKS.md` files under `~/Documents`**. This means tasks in
deeply nested project directories, or in directories outside the configured
workspace, are still counted. This matches the behaviour of `forge due`.

After each sync, the badge counts are refreshed. If new items were captured
from Reminders, a macOS notification is displayed.

### Sync targets

Configured in `config.yaml`:

```yaml
gtd:
  reminders_list: Forge       # Apple Reminders list name
  calendar_name: Forge        # Apple Calendar name
```

Create these in Reminders.app and Calendar.app before your first sync. Forge
will create additional Reminders lists per context as needed (e.g. "Forge • email", "Forge • office") when you sync tasks that have an `@ctx()` tag.

---

## Quick capture

**Cmd+Shift+N** opens a floating capture panel. Type a task and press Return.
The task is appended to `inbox.md` with a generated ID, the inbox count is
updated, and a confirmation notification is shown.

You can also capture from the terminal:

```bash
forge inbox "Buy reagents @ctx(errands)"
```

Or from Neovim:

```
<leader>Fc
```

---

## Permissions

On first launch, macOS will prompt for access to:

- **Reminders** — required for two-way task sync.
- **Calendar** — required for due-date event sync.

Grant both for full functionality. These are declared in the app's
`Info.plist`.

### Privacy and data flow

- Forge.app reads and writes only the Forge directory on your disk
  (configuration, inbox and area files, and project `TASKS.md` files).
- Background sync uses macOS frameworks (EventKit and related APIs) to talk to
  **your** Reminders and Calendar accounts; no data is sent to any Forge
  server.
- The task index at `Forge/.cache/tasks.db` stores file paths, timestamps, and
  cached counts, not full task text.
- You keep full control over where the Forge directory lives (for example on an
  encrypted volume, in a git repository, or in a local-only folder).

---

## Configuration resolution

Forge.app searches for `config.yaml` in this order:

1. `~/Documents/Forge/config.yaml`
2. `~/Documents/Work/Projects/Forge/config.yaml`

The first match is used, and its parent directory becomes the Forge home
directory.

---

## Multi-Mac sync

The Forge source directory (`~/Documents/Forge/`) syncs via iCloud Drive. On
each new Mac:

1. Wait for iCloud to finish downloading.
2. Run `zsh ~/Documents/Forge/build.sh`.
3. The build happens locally; markdown files and configuration are shared.

The Launch Agent ensures Forge.app starts at every login.

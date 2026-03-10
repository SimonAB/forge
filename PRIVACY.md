## Forge privacy overview

Forge is designed as a **local-first, privacy-respecting** project and task manager.
This document summarises what data Forge uses, where it lives, and how it moves.

### What Forge stores

- **Tasks and projects**
  - Stored as plain-text markdown files under your Forge directory (typically
    `~/Documents/Forge`), including:
    - `config.yaml`
    - `tasks/*.md` (inbox and area files, plus generated artefacts like `due.md`)
    - project `TASKS.md` files under your configured `project_roots`
  - You can open and edit all of these files with any editor.

- **Cache and index**
  - Forge maintains a small local SQLite database at `Forge/.cache/tasks.db`.
  - This stores file paths, modification times, sizes, and cached per-file
    counts (overdue, due-today, inbox counts).
  - It does **not** store full task text; that remains in markdown.

- **Preferences and focus**
  - The menubar app stores UI preferences (shortcuts, editor choice, filters)
    in standard macOS preferences.
  - The current focus tag is stored in a `.focus` file in the Forge directory.

### What Forge talks to

- **Apple Reminders and Calendar (optional)**
  - When you enable sync (via `forge sync` or Forge.app), Forge uses macOS
    EventKit APIs to:
    - Create/update/delete Reminders for tasks with `@due` or context tags.
    - Create/update/delete Calendar events for dated tasks.
    - Import new items from the configured Reminders list into `inbox.md`.
    - Keep due dates aligned when events move in Calendar.
  - All of this happens **locally on your Mac**, against the Reminders and
    Calendar accounts already configured in System Settings.
  - Forge does not talk to any third-party servers.

- **No telemetry or remote services**
  - Forge sends **no usage analytics, telemetry, or task content** to any
    external service.
  - Network traffic, if any, is solely whatever your macOS Reminders/Calendar
    accounts already perform via the system.

### Running Forge in more private modes

- **Markdown-only (no sync)**
  - You can use Forge purely as a markdown-based task and project system:
    - Do not grant Reminders/Calendar permissions when prompted, or
    - Leave `gtd.reminders_list` / `gtd.calendar_name` unset in `config.yaml`,
      and avoid calling `forge sync`.
  - All CLI commands and the board app still work against the markdown files.

- **Local-only storage**
  - Place your Forge directory on:
    - A local-only folder (not backed by iCloud or other sync), or
    - An encrypted volume (e.g. FileVault-encrypted disk image).
  - The code and config do not care where the directory lives; only your
    `config.yaml` needs to point at the right `project_roots`.

### Sharing logs and traces

- **CLI logs**
  - `forge sync --verbose` and similar commands may include:
    - File paths in your home directory
    - Task text and inline tags
  - Before pasting logs into an issue, **redact names, emails, and sensitive
    task descriptions**.

- **Profiling samples and traces**
  - Commands like:

    ```bash
    sample <PID> 10 -file forge-menubar-startup.txt
    ```

    produce files that contain stack traces and local paths.

  - Treat these as sensitive:
    - Do not commit them to git.
    - When sharing snippets, strip or replace any personal paths or project
      names.

### Your responsibilities

Forge keeps all data local and under your control, but you remain responsible
for:

- Choosing where the Forge directory lives (and whether it is synced or
  encrypted).
- Managing backup and retention policies for your markdown files.
- Redacting sensitive content before sharing logs or example task files in
  public bug reports.

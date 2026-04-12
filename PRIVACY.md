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
  - When **Forge.app** runs background sync, it may also write
    `Forge/.cache/calendar-snapshot.json` (a short-lived read-only copy of upcoming
    Calendar events: titles, times, calendar names, locations, optional notes and URLs,
    stable event and calendar identifiers, and a per-day grouping) so the `forge` CLI
    can display your schedule without requiring Calendars permission for your terminal app.

- **Preferences and focus**
  - The menubar app stores UI preferences (shortcuts, editor choice, filters)
    in standard macOS preferences.
  - The current focus tag is stored in a `.focus` file in the Forge directory.

### What Forge talks to

- **Apple Reminders (optional)**
  - When you enable sync (via `forge sync` or Forge.app), Forge uses macOS
    EventKit APIs to:
    - Create/update/delete Reminders for tasks with `@due` or context tags.
    - Import new items from the configured Reminders list into `inbox.md`.
    - Keep completion state and due dates aligned between Reminders and markdown.
  - All of this happens **locally on your Mac**, against the Reminders account
    already configured in System Settings.
  - Forge does not talk to any third-party servers.

- **Apple Calendar (optional, read-only)**
  - When you run `forge calendar` or `forge brief` (unless you pass `--no-calendar`), Forge uses macOS
    EventKit to **read** events from your calendars for display in the terminal.
  - Nothing is written back to Calendar, and nothing is sent to Forge servers.
  - Optional `gtd.calendar_include` in `config.yaml` limits which calendar
    **titles** are queried (exact match); if omitted or empty, all event
    calendars are included.

- **No telemetry or remote services**
  - Forge sends **no usage analytics, telemetry, or task content** to any
    external service.
  - Network traffic, if any, is solely whatever your macOS Reminders account
    already performs via the system.

### Running Forge in more private modes

- **Markdown-only (no sync)**
  - You can use Forge purely as a markdown-based task and project system:
    - Do not grant Reminders permission when prompted, or
    - Avoid calling `forge sync`.
  - All CLI commands and the board app still work against the markdown files.

- **No Calendar access**
  - Use `forge brief --no-calendar` for a task-only brief, avoid `forge calendar`, and/or deny Calendars
    permission when prompted. Other commands are unaffected.

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

<h3 id="ai-assistants">AI assistants and local language models</h3>

Pasting `forge brief` output, task lists, or project paths into a **cloud-hosted**
assistant sends that material to the provider’s infrastructure. For **strong
privacy** when using LLM-assisted coding or task workflows, this project
recommends **Ollama with [Pi](https://github.com/badlogic/pi-mono)** — the
minimal coding agent integrated with Ollama (“Ollama Pi” in upstream docs).
Inference can stay on your Mac via Ollama’s local API; prompts and responses do
not need to leave the machine if you use **local** models only.

**Typical setup:**

1. Install **[Ollama](https://ollama.com)** for macOS and ensure the service is
   running (menu bar app or `ollama serve`) so the API is available at
   `http://127.0.0.1:11434`.
2. Pull a **local** model, for example: `ollama pull qwen3-coder` — choose a
   size that fits your RAM and latency expectations.
3. Install Pi: `npm install -g @mariozechner/pi-coding-agent`.
4. Run **`ollama launch pi`** — this wires Ollama in as a provider and starts
   an interactive session. For configuration without launching, use
   **`ollama launch pi --config`**.
5. For privacy, use **local** model names in Pi/Ollama. Avoid cloud-backed
   options (for example models or flags advertised as **cloud**) if you require
   prompts to stay off third-party inference.

**Manual configuration** (without `ollama launch pi`) is documented in Ollama’s
**[Pi integration guide](https://docs.ollama.com/integrations/pi)** (notably
`~/.pi/agent/models.json` and `~/.pi/agent/settings.json`).

**Editors (e.g. Cursor):** Many tools support an OpenAI-compatible **base URL**
pointing at `http://127.0.0.1:11434/v1` with a placeholder API key, so chat can
use Ollama locally; refer to your editor’s settings for “Ollama” or “local LLM”.

### Your responsibilities

Forge keeps all data local and under your control, but you remain responsible
for:

- Choosing where the Forge directory lives (and whether it is synced or
  encrypted).
- Managing backup and retention policies for your markdown files.
- Redacting sensitive content before sharing logs or example task files in
  public bug reports.

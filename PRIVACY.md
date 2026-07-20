## Forge privacy overview

Forge is designed as a **local-first, privacy-respecting** project manager.
This document summarises what data Forge uses, where it lives, and how it moves.

### What Forge stores

- **Projects**
  - Stored as ordinary directories under your configured `project_roots`.
  - Kanban state is stored as **Finder tags** on those directories (workflow column,
    meta tags, and optional assignees such as `#Person`).

- **Cache and index**
  - Forge may maintain small local caches for performance (paths and timestamps).
  - These caches are local-only and exist to avoid repeated filesystem scans.

- **Preferences and focus**
  - The menubar app stores UI preferences (shortcuts, editor choice, filters)
    in standard macOS preferences.
  - The current focus tag is stored in a `.focus` file in the Forge directory.

### What Forge talks to

- **Apple Calendar (optional, read-only)**
  - When you run `forge calendar`, Forge uses macOS EventKit to **read** events
    from your calendars for display in the terminal.
  - Nothing is written back to Calendar, and nothing is sent to Forge servers.
  - Optional `calendar.include` in `config.yaml` (if present) limits which calendar
    **titles** are queried (exact match); if omitted or empty, all event
    calendars are included. Legacy `gtd.calendar_include` is still read as a
    fallback.

- **Sparkle app updates (Forge.app)**
  - The menubar app may check
    [`docs/appcast.xml`](https://raw.githubusercontent.com/SimonAB/forge/main/docs/appcast.xml)
    and download a signed app zip from GitHub Releases. This is update metadata
    and the app binary only — not your board or project content.
  - Disable checks via **Forge → Check for Updates…** preferences if you prefer
    fully offline updates (install new builds yourself).

- **In-app Brief (optional)**
  - Preferences can send a **board + calendar summary** to a configured LLM
    endpoint (typically local **Ollama** at `http://127.0.0.1:11434`). A
    non-loopback base URL will transmit that summary off-machine.
  - Prefer local models; see **AI assistants and local language models** below.

- **OmniFocus (optional)**
  - When `omnifocus.enabled` is true (Preferences → OmniFocus, or config.yaml), Forge may use macOS Automation to run
    OmniJS inside OmniFocus (read inventory; with explicit `--apply` or menubar **OmniFocus Align… → Apply**, create
    `🔥 Forge:` link tags and set flat column tags such as `Watch 🚧`; nested `KanbanStatus/` / legacy `ForgeColumn/`
    remain readable for migration). Data stays on your Mac.
  - Align/apply default to **dry-run**; nothing is written without `--apply` or
    a menubar Apply confirmation.
  - Board **Refresh** may update Finder tags from OF (columns / completed projects) when
    `sync_from_omnifocus` / `sync_completed_project_to_shipped` are enabled.
  - Requires OmniFocus installed and Automation permission for your terminal
    and/or Forge.app.

- **No telemetry**
  - Forge sends **no usage analytics or telemetry**.
  - Aside from Sparkle updates (if enabled), an optional Brief LLM endpoint
    you configure, and optional local OmniFocus Automation, network traffic is
    solely whatever macOS and your accounts already perform via the system.

### Running Forge in more private modes

- **No Calendar access**
  - Avoid `forge calendar`, and/or deny Calendars permission when prompted.
    Other commands are unaffected.

- **Local-only storage**
  - Place your Forge directory on:
    - A local-only folder (not backed by iCloud or other sync), or
    - An encrypted volume (e.g. FileVault-encrypted disk image).
  - The code and config do not care where the directory lives; only your
    `config.yaml` needs to point at the right `project_roots`.

### Sharing logs and traces

- **CLI logs**
  - Verbose commands may include:
    - File paths in your home directory
    - Project names and tag strings
  - Before pasting logs into an issue, **redact names, emails, and sensitive
    project details**.

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

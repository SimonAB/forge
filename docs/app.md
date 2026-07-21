# Forge.app

Forge.app is a macOS **menu bar companion** that runs in the background and
provides quick access to your board and project workflows.

## Setup

### Option A — GitHub release (pre-built app)

Each [GitHub release](https://github.com/SimonAB/forge/releases/latest) includes **`Forge-macos-arm64.app.zip`**. Unzip it and move **`Forge.app`** to `/Applications`. The zip is built with the same layout as `build.sh` (release configuration).

**In-app updates ([Sparkle](https://sparkle-project.org/)):** once Forge is running from a proper **`Forge.app`** bundle (release install or `build.sh`), **Forge → Check for Updates…** and **automatic checks** (about once per day) use the appcast at [`docs/appcast.xml`](https://raw.githubusercontent.com/SimonAB/forge/main/docs/appcast.xml) on `main`. Sparkle downloads a signed **`Forge-macos-arm64.app.zip`** from [GitHub Releases](https://github.com/SimonAB/forge/releases) and installs it using the standard Sparkle flow (including **Install on quit** when offered). Maintainer signing setup: **`packaging/SPARKLE_SIGNING.md`**.

### Option B — `build.sh` (from source)

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
3. **App bundle** — assembles `/Applications/Forge.app` with the compiled
   binary, an `Info.plist`, and an optional generated icon.
4. **Launch Agent** — installs
   `~/Library/LaunchAgents/com.forge.menubar.plist` so Forge.app starts
   automatically at login.
5. **CLI install (optional)** — Forge.app bundles `forge` at `Contents/Resources/bin/forge`.
   To put it on your `$PATH`, open **Forge → Preferences… → Install CLI…** and choose:
   - `~/bin/forge` (recommended; no admin)
   - `/usr/local/bin/forge` (admin)

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
| Red number | URGENT projects |
| Orange number | Non-urgent attention needed (if configured) |
| No badge | Nothing urgent |

---

## Menu items

| Item | Shortcut | Description |
|------|----------|-------------|
| **Board** | Cmd+B | Opens the native Kanban board window |
| **OmniFocus Align…** | — | When OmniFocus integration is enabled: dry-run alignment plan; **Apply** writes OF/Finder tags after confirmation |
| **Open Board in Terminal** | — | Runs `forge board` in your terminal |
| **Quit Forge** | Cmd+Q | Exits Forge.app |
| **Check for Updates…** | — | Sparkle: compares with **`docs/appcast.xml`** and offers signed **`Forge-macos-arm64.app.zip`** |

### OmniFocus (optional)

Enable under **Preferences → OmniFocus**. With `sync_on_move`, board column moves mirror onto linked OF tasks. With `sync_from_omnifocus`, board **Refresh** pulls OF column tags onto Finder (and clears stacked leftover OF kanban tags on those folders). Finder→OF is not rewritten from Refresh. With `sync_completed_project_to_shipped`, a completed/dropped OF **project** moves the matching Finder folder to **Shipped** on Refresh.

CLI: `forge omnifocus doctor` → `align` (dry-run) → `align --apply`. See [cli.md](cli.md) and `packaging/omnifocus/README.md`.

---

## Quick capture

Forge no longer includes a GTD task system, so there is no quick-capture panel.

## Permissions

On first launch, macOS will prompt for access to:

- **Calendars** — only if you use CLI commands that read Calendar (`forge calendar`). Forge does not modify calendar data.

Grant access for full functionality. This is declared in the app's
`Info.plist`.

### Privacy and data flow

- Forge.app reads and writes only the Forge directory on your disk
  (configuration and caches), plus Finder tags on your project folders.
- Optional **`forge calendar`** reads Calendar events locally for terminal output only (read-only).
- **Sparkle** may check for app updates and download a signed zip from GitHub Releases
  (app binary only — not your board content). See **`PRIVACY.md`**.
- **Preferences → Brief** can send a board/calendar summary to **local Ollama**
  (loopback by default). A non-loopback base URL may transmit data off-machine.
- **Preferences → Hermes** checks and runs setup for the recommended local
  assistant (Hermes + Ollama + `forge-board` skill). See **`docs/hermes.md`**.
- You keep full control over where the Forge directory lives (for example on an
  encrypted volume, in a git repository, or in a local-only folder).
- If you use an **LLM** with Forge output, prefer **Hermes with Ollama** for local
  inference; see **`docs/hermes.md`** and **`PRIVACY.md`** (**AI assistants and local language models**).

---

## Brief (Preferences)

Open **Forge → Preferences… → Brief** to generate an LLM-assisted board summary via **local Ollama**.

- Default base URL: `http://127.0.0.1:11434/v1`
- Use loopback URLs only for privacy-first use
- Review proposed column/tag changes before applying them

For the full local kanban assistant (skills, terminal, tools), use **Preferences → Hermes**.

---

## Hermes (Preferences)

Open **Forge → Preferences… → Hermes** for privacy-first local assistant setup.

- **Check setup** — Ollama, Hermes, `forge` CLI, and `forge-board` skill status
- **Run setup in Terminal** — runs `python3 scripts/setup-hermes-forge.py`
- **Open guide** — `docs/hermes.md`

PATH checks use Forge’s shared resolver (`ExecutablePathResolver`): Homebrew and
common user prefixes (`~/bin`, `~/.local/bin`, `~/.cargo/bin`) are searched even
when Forge.app is launched from Finder (which otherwise sees a minimal GUI
`PATH`). The same layout is applied when Forge opens a Terminal window.

See **`docs/hermes.md`** for full instructions.

---

## Configuration resolution

Forge.app searches for `config.yaml` in this order:

1. The most recently selected path via **Forge → Preferences… → Choose config…**.
2. `~/Documents/Forge/config.yaml`
3. `~/Documents/Work/Projects/Forge/config.yaml`

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

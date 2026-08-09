# Forge

<p align="center">
<a href="https://simonab.github.io/forge/"><img src="https://img.shields.io/badge/site-GitHub%20Pages-4285F4?style=for-the-badge&amp;logo=githubpages&amp;logoColor=white" alt="Project website on GitHub Pages" /></a>
</p>

<p align="center">
  <a href="https://github.com/SimonAB/forge/releases/latest"><img src="https://img.shields.io/github/v/release/SimonAB/forge?style=for-the-badge&amp;logo=github&amp;label=release" alt="Latest release" /></a>
  <a href="https://github.com/SimonAB/forge/releases/latest/download/forge-macos-arm64.zip"><img src="https://img.shields.io/badge/download-CLI%20%28Apple%20Silicon%29-ea580c?style=for-the-badge&amp;logo=apple&amp;logoColor=white" alt="Download CLI zip (arm64)" /></a>
  <a href="https://github.com/SimonAB/forge/blob/main/CHANGELOG.md"><img src="https://img.shields.io/badge/changelog-Keep%20a%20Changelog-78716c?style=for-the-badge&amp;logo=gitbook&amp;logoColor=white" alt="Changelog" /></a>
</p>

<p align="center">
  <a href="Package.swift"><img src="https://img.shields.io/badge/Swift-6-F05138?style=for-the-badge&amp;logo=swift&amp;logoColor=white" alt="Swift 6" /></a>
  <a href="https://github.com/SimonAB/forge#requirements"><img src="https://img.shields.io/badge/macOS-14%2B-000000?style=for-the-badge&amp;logo=apple&amp;logoColor=white" alt="macOS 14 or later" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-7CB342?style=for-the-badge" alt="Apache License 2.0" /></a>
  <a href="PRIVACY.md"><img src="https://img.shields.io/badge/Privacy-local--first-57534e?style=for-the-badge&amp;logo=lockprivacy&amp;logoColor=white" alt="Local-first privacy" /></a>
  <a href="#who-is-forge-for"><img src="https://img.shields.io/badge/Kanban-Finder%20tags-d97706?style=for-the-badge" alt="Kanban with Finder tags" /></a>
</p>

<p align="center"><strong>Local, Finder-tagged kanban project management for macOS.</strong><br />
Kanban board · Finder tags · ordinary folders · no Forge-hosted servers.</p>

---

Forge is a **kanban board** for project tracking built on ordinary folders and
**Finder tags**. It is local-first: your projects live in your own directories,
and Forge does not require any hosted service.

## Who is Forge for?

Forge is for people who think in files and folders first, and who want a
transparent system built on ordinary directories, Finder tags, and markdown
files.

Forge works well if you:

- Prefer plain-text systems you can search and version-control with git, alongside Finder tags.
- Want project state driven by Finder tags (including assignees as `#Person` tags).
- Want a kanban view for projects without a hosted backend.
- Care about local-first privacy: Forge uses no hosted servers.

For a longer tour of concepts and workflows, see the user manual in
[`docs/forge-manual.md`](docs/forge-manual.md).

## Components

| Component | Description |
|-----------|-------------|
| [`forge` CLI](docs/cli.md) | Command-line interface for board views, tags, calendar, and optional OmniFocus |
| [Forge.app](docs/app.md) | Menu bar companion and board window |
| [Hermes + Ollama](docs/hermes.md) | Privacy-first local assistant (`forge-board` skill) |
| [Neovim plugin](docs/neovim.md) | Keymaps, commands, and dashboard integration via `forge-nvim.lua` |

## Project website

The public site is <a href="https://simonab.github.io/forge/"><img src="docs/favicon.svg" alt="" width="18" height="18" /> <strong>simonab.github.io/forge</strong></a>
(fork: `https://<user>.github.io/<repo>/`). Landing page: [`docs/index.html`](docs/index.html)
with [`docs/assets/site.css`](docs/assets/site.css) and [`docs/favicon.svg`](docs/favicon.svg).

The **full documentation** is also published as static HTML next to the landing page, generated from the same markdown as the repo (`README.md`, `CHANGELOG.md`, `PRIVACY.md`, `docs/cli.md`, `docs/app.md`, `docs/hermes.md`, `docs/neovim.md`, `docs/forge-manual.md`, and the landing-page feature guides):

| Page | Source |
|------|--------|
| [`docs/kanban.html`](docs/kanban.html) | [`docs/kanban.md`](docs/kanban.md) |
| [`docs/folders.html`](docs/folders.html) | [`docs/folders.md`](docs/folders.md) |
| [`docs/finder-tags.html`](docs/finder-tags.html) | [`docs/finder-tags.md`](docs/finder-tags.md) |
| [`docs/cli-and-apps.html`](docs/cli-and-apps.html) | [`docs/cli-and-apps.md`](docs/cli-and-apps.md) |
| [`docs/omnifocus.html`](docs/omnifocus.html) | [`docs/omnifocus.md`](docs/omnifocus.md) |
| [`docs/cli.html`](docs/cli.html) | [`docs/cli.md`](docs/cli.md) |
| [`docs/app.html`](docs/app.html) | [`docs/app.md`](docs/app.md) |
| [`docs/hermes.html`](docs/hermes.html) | [`docs/hermes.md`](docs/hermes.md) |
| [`docs/neovim.html`](docs/neovim.html) | [`docs/neovim.md`](docs/neovim.md) |
| [`docs/manual.html`](docs/manual.html) | [`docs/forge-manual.md`](docs/forge-manual.md) |
| [`docs/privacy.html`](docs/privacy.html) | [`PRIVACY.md`](PRIVACY.md) |
| [`docs/readme.html`](docs/readme.html) | [`README.md`](README.md) |
| [`docs/changelog.html`](docs/changelog.html) | [`CHANGELOG.md`](CHANGELOG.md) |

Regenerate the `*.html` files after editing documentation (also done automatically
in `.github/workflows/pages.yml` on pushes to `main`):

```bash
pip install -r docs/requirements.txt   # once per environment
python3 docs/build_site.py
```

To publish with **GitHub Pages**, open **Settings → Pages**, set **Build and deployment**
**Source** to **GitHub Actions** (not “Deploy from a branch”).

## Quick start

Pre-built binaries (macOS 14+, **Apple Silicon arm64**):

- **CLI:** [`forge-macos-arm64.zip`](https://github.com/SimonAB/forge/releases/latest/download/forge-macos-arm64.zip) (includes `LICENSE` and install notes).
- **Menu bar app:** [`Forge-macos-arm64.app.zip`](https://github.com/SimonAB/forge/releases/latest/download/Forge-macos-arm64.app.zip) — unzip and drag `Forge.app` into **Applications**. Updates use **Sparkle** ([`docs/appcast.xml`](https://raw.githubusercontent.com/SimonAB/forge/main/docs/appcast.xml)): **Check for Updates…** and periodic automatic checks.

See [all releases](https://github.com/SimonAB/forge/releases). Intel Macs: build from
source with `build.sh`. Developers syncing source via iCloud typically still use `build.sh` below so the CLI and app stay in sync with local changes.

```bash
# On a fresh Mac where Forge source has synced via iCloud Drive:
zsh ~/Documents/Forge/build.sh
```

This builds the Swift project, creates `/Applications/Forge.app`, and registers
a Launch Agent so the menu bar app starts at login. To put `forge` on your
terminal `$PATH`, use **Forge → Preferences… → Install CLI…**. The script only
touches the Forge source directory, `~/.forge-build`, and your local
application folders; it never sends any data off your Mac. See
[setup details](docs/app.md#setup).

### Requirements

- macOS 14 or later.
- Xcode or Xcode Command Line Tools (for the Swift toolchain).
- Python 3 with Pillow (`pip3 install Pillow`) if you want the generated app icon
  (Forge will still work without this; a default icon is used).

Run `build.sh` once per Mac after your Forge directory has synchronised (for
example via iCloud Drive or git). Your tasks and configuration remain plain-text
files in the Forge directory, shared across machines however you choose to sync.

## Privacy and data model

- All projects are ordinary directories under your configured workspace roots.
  Kanban state is stored as **Finder tags** on those directories.
- Forge keeps small local caches for performance. It does not require any Forge-hosted
  backend.
- You are free to keep the Forge directory under git, on an encrypted volume,
  or in a local-only folder if you prefer not to sync via any cloud service.

See `PRIVACY.md` for a fuller description of what Forge stores, how sync works,
and how to run without Calendar access or with local-only storage.

If you use an **AI assistant** with Forge output (for example pasting `forge brief`
into a chat), the privacy-first recommendation is **Hermes Agent with Ollama**
on your Mac (`python3 scripts/setup-hermes-forge.py` — see **`docs/hermes.md`**).
You may also use a **cloud** assistant when you need more capability — Forge stays
agnostic. See **AI assistants and local language models** in [`PRIVACY.md`](PRIVACY.md#ai-assistants) for setup and trade-offs.

## AI assistants (optional)

If you use a coding assistant with this repo, **`AGENTS.md`** is the operating manual
(Hephaestus stance, OmniFocus integration, kanban rules, brief format). Supporting
material: **`.cursor/rules/`** (CLI, workflows, GTD tasks), **`docs/hermes.md`**
(Hermes + Ollama setup), **`PROJECT_TEMPLATE.md`** (new project READMEs), and
**`python3 scripts/forge-brief.py`** for read-only board briefs without any LLM.

## Directory layout

```
~/Documents/Forge/              Forge home (synced via iCloud Drive)
├── AGENTS.md                   Assistant operating manual (kanban + OmniFocus)
├── config.yaml                 Configuration (board columns, workspace roots, tags)
├── build.sh                  Per-Mac build & install script
├── generate_icon.py            App icon generator (requires Pillow)
├── Sources/                    Swift source code
├── Package.swift               Swift package manifest
└── docs/                       Documentation
    ├── cli.md
    ├── app.md
    └── neovim.md

~/Documents/Work/Projects/      Workspace (project directories)
├── ProjectA/
├── ProjectB/
└── ...
```

Projects are ordinary directories. Their kanban column is stored as a **Finder
tag** (visible in Finder and readable by Spotlight).

## Configuration

Start from [`config.sample.yaml`](config.sample.yaml) and copy it to
`config.yaml`, then adjust paths and names to match your setup. Key sections:

- **`project_roots`** — one or more directories whose subfolders are Forge projects (legacy `workspace` still supported).
- **`project_scan_depth`** — how many levels to scan under each root (`1` = direct children only; `2` = also inside untagged grouping folders).
- **`board.columns`** — ordered kanban columns, each mapped to a Finder tag.
- **`board.meta_tags`** — supplementary tags (e.g. Collab, Student, URGENT), used for per-project flags and for the board's Radar view.
- **`terminal`** — preferred terminal app (`auto`, `iTerm`, `Terminal.app`).

## Multi-Mac sync

Source code and markdown files sync automatically via **iCloud Drive**. The
compiled `.build` directory is kept outside iCloud at `~/.forge-build` (symlinked
into the source tree). Run `build.sh` on each new Mac to build locally.

## Licence

Forge is distributed under the Apache License, Version 2.0. See the `LICENSE`
file in this repository for the full text.

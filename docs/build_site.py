#!/usr/bin/env python3
"""
Regenerate static HTML documentation pages from markdown sources.

Run from the repository root::

    pip install -r docs/requirements.txt
    python3 docs/build_site.py

Outputs HTML files next to ``index.html`` under ``docs/`` for GitHub Pages.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

try:
    import markdown
except ImportError:
    print("Missing dependency: pip install -r docs/requirements.txt", file=sys.stderr)
    sys.exit(1)

DOCS_DIR = Path(__file__).resolve().parent
REPO_ROOT = DOCS_DIR.parent

# Bust GitHub Pages CDN/browser caches when CSS/JS behaviour changes.
DOCS_ASSET_VER = "4"

GITHUB_BLOB = "https://github.com/SimonAB/forge/blob/main"

NAV_ITEMS: tuple[tuple[str, str, str], ...] = (
    ("index.html", "Home", "home"),
    ("cli.html", "CLI", "cli"),
    ("app.html", "Forge.app", "app"),
    ("hermes.html", "Hermes", "hermes"),
    ("neovim.html", "Neovim", "neovim"),
    ("manual.html", "Manual", "manual"),
    ("privacy.html", "Privacy", "privacy"),
    ("readme.html", "Readme", "readme"),
    ("changelog.html", "Changelog", "changelog"),
)

MD_EXTENSIONS = (
    "markdown.extensions.extra",
    "markdown.extensions.sane_lists",
    "markdown.extensions.toc",
)

# Inline before first paint: pinned light/dark only. "system" leaves classes off so
# site.css @media (prefers-color-scheme: dark) applies. Kept in sync with docs/index.html.
THEME_INLINE_BOOTSTRAP = """    <script>
      (function () {
        try {
          var stored = localStorage.getItem("forge-theme-appearance");
          var mode =
            stored === "light" || stored === "dark" || stored === "system"
              ? stored
              : "system";
          var root = document.documentElement;
          if (mode === "light") {
            root.classList.add("light");
          } else if (mode === "dark") {
            root.classList.add("dark");
          }
        } catch (err) {
          /* localStorage unavailable — CSS alone follows prefers-color-scheme */
        }
      })();
    </script>
"""


def _nav_html(active: str) -> str:
    parts = ['<nav class="site-nav__links" aria-label="Main navigation">']
    for href, label, slug in NAV_ITEMS:
        cls = "site-nav__link is-active" if slug == active else "site-nav__link"
        parts.append(f'  <a class="{cls}" href="{href}">{label}</a>')
    parts.append(
        '  <a class="site-nav__link" href="https://github.com/SimonAB/forge" '
        'target="_blank" rel="noopener noreferrer">GitHub</a>'
    )
    parts.append("</nav>")
    return "\n".join(parts)


def _page_shell(*, title: str, description: str, active: str, main_html: str) -> str:
    nav = _nav_html(active)
    return (
        f"""<!DOCTYPE html>
<html lang="en-GB" dir="ltr">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>{title}</title>
    <meta name="description" content="{description}" />
    <link rel="icon" type="image/svg+xml" href="favicon.svg" />
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link
      href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap"
      rel="stylesheet"
    />
    <link rel="stylesheet" href="assets/site.css?v={DOCS_ASSET_VER}" />
"""
        + THEME_INLINE_BOOTSTRAP
        + f"""
  </head>
  <body>
    <a href="#main" class="visually-hidden">Skip to content</a>
    <header class="site-nav">
      <div class="site-nav__inner">
        <a class="site-nav__brand" href="index.html">Forge</a>
        {nav}
        <div class="site-nav__actions">
          <button
            type="button"
            class="theme-toggle"
            id="theme-toggle"
            aria-label="Toggle dark mode"
            title="Toggle theme"
          >
            <span class="theme-toggle__icon theme-toggle__icon--sun" aria-hidden="true">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <circle cx="12" cy="12" r="4" />
                <path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41" />
              </svg>
            </span>
            <span class="theme-toggle__icon theme-toggle__icon--moon" aria-hidden="true" hidden>
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z" />
              </svg>
            </span>
          </button>
          <a
            class="btn btn--alt"
            href="https://github.com/SimonAB/forge"
            target="_blank"
            rel="noopener noreferrer"
            >View on GitHub</a
          >
        </div>
      </div>
    </header>
    <main id="main" class="doc-page">
      <article class="doc-content">
{main_html}
      </article>
    </main>
    <footer class="site-footer">
      <p>
        <a href="index.html">Home</a>
        · Source markdown in the
        <a href="https://github.com/SimonAB/forge" target="_blank" rel="noopener noreferrer">repository</a>
      </p>
      <p>Released under the Apache License, Version 2.0.</p>
    </footer>
    <script src="assets/theme.js?v={DOCS_ASSET_VER}"></script>
  </body>
</html>
"""
    )


def _escape_meta(text: str) -> str:
    return text.replace("&", "&amp;").replace('"', "&quot;")


def _strip_front_matter(text: str) -> str:
    """Drop a leading YAML front-matter block (``---`` … ``---``)."""
    if not text.startswith("---"):
        return text
    end = text.find("\n---", 3)
    if end == -1:
        return text
    return text[end + 4 :].lstrip("\n")


def _convert_markdown(text: str) -> str:
    md = markdown.Markdown(extensions=list(MD_EXTENSIONS))
    return md.convert(_strip_front_matter(text))


def _rewrite_internal_links(html: str) -> str:
    """Point documentation links at generated HTML; send repo-only paths to GitHub."""

    def sub(pattern: str, repl: str, s: str) -> str:
        return re.sub(pattern, repl, s)

    html = sub(r'href="docs/forge-manual\.md(#[^"]*)?"', r'href="manual.html\1"', html)
    html = sub(r'href="docs/cli\.md(#[^"]*)?"', r'href="cli.html\1"', html)
    html = sub(r'href="docs/app\.md(#[^"]*)?"', r'href="app.html\1"', html)
    html = sub(r'href="docs/hermes\.md(#[^"]*)?"', r'href="hermes.html\1"', html)
    html = sub(r'href="docs/neovim\.md(#[^"]*)?"', r'href="neovim.html\1"', html)
    html = sub(r'href="docs/kanban\.md(#[^"]*)?"', r'href="kanban.html\1"', html)
    html = sub(r'href="docs/folders\.md(#[^"]*)?"', r'href="folders.html\1"', html)
    html = sub(r'href="docs/finder-tags\.md(#[^"]*)?"', r'href="finder-tags.html\1"', html)
    html = sub(r'href="docs/cli-and-apps\.md(#[^"]*)?"', r'href="cli-and-apps.html\1"', html)
    html = sub(r'href="docs/omnifocus\.md(#[^"]*)?"', r'href="omnifocus.html\1"', html)
    html = sub(r'href="docs/index\.html(#[^"]*)?"', r'href="index.html\1"', html)
    html = sub(r'href="PRIVACY\.md(#[^"]*)?"', r'href="privacy.html\1"', html)
    html = sub(r'href="README\.md(#[^"]*)?"', r'href="readme.html\1"', html)
    html = sub(r'href="CHANGELOG\.md(#[^"]*)?"', r'href="changelog.html\1"', html)
    html = sub(r'href="forge-manual\.md(#[^"]*)?"', r'href="manual.html\1"', html)
    html = sub(r'href="cli\.md(#[^"]*)?"', r'href="cli.html\1"', html)
    html = sub(r'href="app\.md(#[^"]*)?"', r'href="app.html\1"', html)
    html = sub(r'href="hermes\.md(#[^"]*)?"', r'href="hermes.html\1"', html)
    html = sub(r'href="neovim\.md(#[^"]*)?"', r'href="neovim.html\1"', html)
    html = sub(r'href="kanban\.md(#[^"]*)?"', r'href="kanban.html\1"', html)
    html = sub(r'href="folders\.md(#[^"]*)?"', r'href="folders.html\1"', html)
    html = sub(r'href="finder-tags\.md(#[^"]*)?"', r'href="finder-tags.html\1"', html)
    html = sub(r'href="cli-and-apps\.md(#[^"]*)?"', r'href="cli-and-apps.html\1"', html)
    html = sub(r'href="omnifocus\.md(#[^"]*)?"', r'href="omnifocus.html\1"', html)
    html = sub(r'href="\.\./PRIVACY\.md(#[^"]*)?"', r'href="privacy.html\1"', html)
    html = sub(r'href="\.\./README\.md(#[^"]*)?"', r'href="readme.html\1"', html)
    html = sub(r'href="\.\./CHANGELOG\.md(#[^"]*)?"', r'href="changelog.html\1"', html)
    html = sub(r'href="docs/assets/', 'href="assets/', html)
    html = sub(r'src="docs/favicon\.svg"', 'src="favicon.svg"', html)
    html = sub(r'href="docs/favicon\.svg"', 'href="favicon.svg"', html)

    html = sub(
        r'href="config\.sample\.yaml(#[^"]*)?"',
        rf'href="{GITHUB_BLOB}/config.sample.yaml"',
        html,
    )
    html = sub(
        r'href="packaging/omnifocus/README\.md(#[^"]*)?"',
        rf'href="{GITHUB_BLOB}/packaging/omnifocus/README.md\1"',
        html,
    )
    html = sub(
        r'href="\.\./AGENTS\.md(#[^"]*)?"',
        rf'href="{GITHUB_BLOB}/AGENTS.md\1"',
        html,
    )
    html = sub(
        r'href="\.\./\.hermes/skills/forge-board/SKILL\.md(#[^"]*)?"',
        rf'href="{GITHUB_BLOB}/.hermes/skills/forge-board/SKILL.md\1"',
        html,
    )

    return html


def build_page(
    *,
    source: Path,
    out_name: str,
    page_title: str,
    description: str,
    active: str,
) -> None:
    text = source.read_text(encoding="utf-8")
    body = _convert_markdown(text)
    body = _rewrite_internal_links(body)
    out = DOCS_DIR / out_name
    full = _page_shell(
        title=_escape_meta(f"{page_title} · Forge"),
        description=_escape_meta(description),
        active=active,
        main_html=body,
    )
    out.write_text(full, encoding="utf-8")
    print(f"Wrote {out.relative_to(REPO_ROOT)}")


def main() -> None:
    build_page(
        source=DOCS_DIR / "kanban.md",
        out_name="kanban.html",
        page_title="Kanban",
        description="Finder-tag kanban columns, Radar, and where to work the board.",
        active="",
    )
    build_page(
        source=DOCS_DIR / "folders.md",
        out_name="folders.html",
        page_title="Folders first",
        description="Projects as ordinary directories, project roots, and local visibility.",
        active="",
    )
    build_page(
        source=DOCS_DIR / "finder-tags.md",
        out_name="finder-tags.html",
        page_title="Finder tags",
        description="Workflow columns, meta tags, assignees, and Finder/Spotlight visibility.",
        active="",
    )
    build_page(
        source=DOCS_DIR / "cli-and-apps.md",
        out_name="cli-and-apps.html",
        page_title="CLI & apps",
        description="Forge CLI, Forge.app, and Neovim on the same folders-and-tags model.",
        active="",
    )
    build_page(
        source=DOCS_DIR / "omnifocus.md",
        out_name="omnifocus.html",
        page_title="OmniFocus",
        description="Optional OmniFocus bridge: doctor, align, Refresh, and sync directions.",
        active="",
    )
    build_page(
        source=DOCS_DIR / "cli.md",
        out_name="cli.html",
        page_title="CLI reference",
        description="Forge command-line interface: boards, tasks, sync, review, and lint.",
        active="cli",
    )
    build_page(
        source=DOCS_DIR / "app.md",
        out_name="app.html",
        page_title="Forge.app",
        description="Menu bar companion: sync, quick capture, overdue badges, and setup.",
        active="app",
    )
    build_page(
        source=DOCS_DIR / "hermes.md",
        out_name="hermes.html",
        page_title="Hermes + Ollama",
        description="Privacy-first local assistant setup for Forge with Hermes and Ollama.",
        active="hermes",
    )
    build_page(
        source=DOCS_DIR / "neovim.md",
        out_name="neovim.html",
        page_title="Neovim integration",
        description="Keymaps, commands, and dashboard integration for Forge in Neovim.",
        active="neovim",
    )
    build_page(
        source=DOCS_DIR / "forge-manual.md",
        out_name="manual.html",
        page_title="Forge manual",
        description="Longer-form guide to using Forge for project and task management.",
        active="manual",
    )
    build_page(
        source=REPO_ROOT / "PRIVACY.md",
        out_name="privacy.html",
        page_title="Privacy",
        description="What Forge stores locally, how sync works, and privacy-minded options.",
        active="privacy",
    )
    build_page(
        source=REPO_ROOT / "README.md",
        out_name="readme.html",
        page_title="Readme",
        description="Forge overview: kanban, GTD, configuration, task format, and directory layout.",
        active="readme",
    )
    build_page(
        source=REPO_ROOT / "CHANGELOG.md",
        out_name="changelog.html",
        page_title="Changelog",
        description="Version history and notable changes to Forge.",
        active="changelog",
    )


if __name__ == "__main__":
    main()

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

GITHUB_BLOB = "https://github.com/SimonAB/forge/blob/main"

NAV_ITEMS: tuple[tuple[str, str, str], ...] = (
    ("index.html", "Home", "home"),
    ("cli.html", "CLI", "cli"),
    ("app.html", "Forge.app", "app"),
    ("neovim.html", "Neovim", "neovim"),
    ("manual.html", "Manual", "manual"),
    ("privacy.html", "Privacy", "privacy"),
    ("readme.html", "Readme", "readme"),
)

MD_EXTENSIONS = (
    "markdown.extensions.extra",
    "markdown.extensions.sane_lists",
)


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
    return f"""<!DOCTYPE html>
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
    <link rel="stylesheet" href="assets/site.css" />
    <script>
      (function () {{
        var stored = localStorage.getItem("forge-theme-appearance");
        var dark =
          stored === "dark" ||
          (!stored && window.matchMedia("(prefers-color-scheme: dark)").matches);
        if (dark) document.documentElement.classList.add("dark");
      }})();
    </script>
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
    <script src="assets/theme.js"></script>
  </body>
</html>
"""


def _escape_meta(text: str) -> str:
    return text.replace("&", "&amp;").replace('"', "&quot;")


def _convert_markdown(text: str) -> str:
    md = markdown.Markdown(extensions=list(MD_EXTENSIONS))
    return md.convert(text)


def _rewrite_internal_links(html: str) -> str:
    """Point documentation links at generated HTML; send repo-only paths to GitHub."""

    def sub(pattern: str, repl: str, s: str) -> str:
        return re.sub(pattern, repl, s)

    html = sub(r'href="docs/forge-manual\.md(#[^"]*)?"', r'href="manual.html\1"', html)
    html = sub(r'href="docs/cli\.md(#[^"]*)?"', r'href="cli.html\1"', html)
    html = sub(r'href="docs/app\.md(#[^"]*)?"', r'href="app.html\1"', html)
    html = sub(r'href="docs/neovim\.md(#[^"]*)?"', r'href="neovim.html\1"', html)
    html = sub(r'href="docs/index\.html(#[^"]*)?"', r'href="index.html\1"', html)
    html = sub(r'href="PRIVACY\.md(#[^"]*)?"', r'href="privacy.html\1"', html)
    html = sub(r'href="README\.md(#[^"]*)?"', r'href="readme.html\1"', html)
    html = sub(r'href="docs/assets/', 'href="assets/', html)
    html = sub(r'src="docs/favicon\.svg"', 'src="favicon.svg"', html)
    html = sub(r'href="docs/favicon\.svg"', 'href="favicon.svg"', html)

    html = sub(
        r'href="config\.sample\.yaml(#[^"]*)?"',
        rf'href="{GITHUB_BLOB}/config.sample.yaml"',
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


if __name__ == "__main__":
    main()

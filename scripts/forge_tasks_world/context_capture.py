#!/usr/bin/env python3
"""Context-aware inbox capture resolution (macOS Services + portable CLI).

Priority when several signals are present:

1. Files (Finder / ``--file``)
2. App context — Mail selection, browser tab URL (macOS only)
3. Selected / provided text (URI sniff or plain note)

Selected text is attached as a **note** when a richer primary (mail / file /
URL) is chosen. On Linux there is no Mail/browser frontmost detection; files,
text, and explicit ``--link`` remain the portable path.
"""

from __future__ import annotations

import platform
import subprocess
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Callable
from urllib.parse import urlparse

from .capture import selected_mail_messages, sniff_clipboard_link

MAIL_BUNDLE = "com.apple.mail"
FINDER_BUNDLE = "com.apple.finder"
BROWSER_BUNDLES = {
    "com.apple.Safari": "safari",
    "com.google.Chrome": "chrome",
    "company.thebrowser.Browser": "arc",
    "com.brave.Browser": "brave",
    "com.microsoft.edgemac": "edge",
    "org.mozilla.firefox": "firefox",
}
BROWSER_APP_NAMES = {
    "chrome": "Google Chrome",
    "arc": "Arc",
    "brave": "Brave Browser",
    "edge": "Microsoft Edge",
}


@dataclass(frozen=True)
class ResolvedCapture:
    """One inbox item to create from context."""

    title: str
    link: str | None = None
    kind: str | None = None
    note: str | None = None
    file_path: str | None = None
    strategy: str = "text"


def is_macos() -> bool:
    """Return True on macOS."""
    return sys.platform == "darwin"


def frontmost_bundle_id() -> str | None:
    """Return the frontmost app bundle id on macOS, else None."""
    if not is_macos():
        return None
    script = (
        'tell application "System Events" to get bundle identifier of '
        "first application process whose frontmost is true"
    )
    result = subprocess.run(
        ["osascript", "-e", script],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return None
    bundle = (result.stdout or "").strip()
    return bundle or None


def browser_tab_url(kind: str) -> str | None:
    """Return the front tab URL for a known macOS browser, if available."""
    if not is_macos():
        return None
    if kind == "safari":
        script = 'tell application "Safari" to get URL of front document'
    elif kind in BROWSER_APP_NAMES:
        app = BROWSER_APP_NAMES[kind]
        script = f'tell application "{app}" to get URL of active tab of front window'
    else:
        return None
    result = subprocess.run(
        ["osascript", "-e", script],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return None
    url = (result.stdout or "").strip()
    if url.lower().startswith(("http://", "https://")):
        return url
    return None


def _title_from_url(url: str) -> str:
    """Build a short title from a URL."""
    parsed = urlparse(url)
    host = parsed.netloc or "URL"
    path = (parsed.path or "").rstrip("/")
    if path and path != "/":
        leaf = path.split("/")[-1] or path
        return f"{host}/{leaf}"[:120]
    return host[:120]


def _note_from_selection(text: str | None, *, primary_uri: str | None = None) -> str | None:
    """Return selected text as a note when it adds information beyond the primary URI."""
    if not text:
        return None
    cleaned = text.strip()
    if not cleaned:
        return None
    if primary_uri and cleaned == primary_uri:
        return None
    sniffed = sniff_clipboard_link(cleaned)
    if sniffed and primary_uri and sniffed[1] == primary_uri:
        return None
    return cleaned


def resolve_captures(
    *,
    files: list[Path] | None = None,
    text: str | None = None,
    prefer: str = "auto",
    frontmost: str | None = None,
    mail_fetcher: Callable[[], list[dict[str, str]]] | None = None,
    browser_fetcher: Callable[[str], str | None] | None = None,
    platform_name: str | None = None,
) -> list[ResolvedCapture]:
    """Resolve zero or more captures from files, app context, and text.

    ``prefer`` is ``auto``, ``mail``, ``file``, ``browser``, or ``text``.
    Inject fetchers / ``frontmost`` in tests. On non-macOS, Mail/browser
    auto-detection is skipped unless ``prefer`` forces mail/browser (which then
    needs a working fetcher).
    """
    file_list = [Path(p).expanduser() for p in (files or []) if str(p).strip()]
    selection = (text or "").strip() or None
    prefer = (prefer or "auto").strip().lower()
    plat = platform_name or platform.system()
    darwin = plat == "Darwin"

    if frontmost is None and prefer == "auto" and darwin:
        frontmost = frontmost_bundle_id()

    mail_fetch = mail_fetcher or selected_mail_messages
    browser_fetch = browser_fetcher or browser_tab_url

    # 1. Files win.
    if file_list and prefer in ("auto", "file"):
        note = _note_from_selection(selection)
        out: list[ResolvedCapture] = []
        for index, path in enumerate(file_list):
            out.append(
                ResolvedCapture(
                    title=f"File: {path.name}",
                    kind="file",
                    note=note if index == 0 else None,
                    file_path=str(path),
                    strategy="file",
                )
            )
        return out

    want_mail = prefer == "mail" or (
        prefer == "auto" and darwin and frontmost == MAIL_BUNDLE
    )
    if want_mail:
        try:
            messages = mail_fetch()
        except RuntimeError:
            messages = []
        if messages:
            note = _note_from_selection(selection)
            return [
                ResolvedCapture(
                    title=msg["title"],
                    link=msg.get("uri") or None,
                    kind="mail" if msg.get("uri") else None,
                    note=note if index == 0 else None,
                    strategy="mail",
                )
                for index, msg in enumerate(messages)
            ]
        if prefer == "mail":
            return []

    browser_kind = BROWSER_BUNDLES.get(frontmost or "")
    want_browser = prefer == "browser" or (prefer == "auto" and darwin and browser_kind)
    if want_browser and browser_kind:
        url = browser_fetch(browser_kind)
        if url:
            return [
                ResolvedCapture(
                    title=_title_from_url(url),
                    link=url,
                    kind="url",
                    note=_note_from_selection(selection, primary_uri=url),
                    strategy="browser",
                )
            ]
        if prefer == "browser":
            return []

    # 3. Text / URI selection.
    if selection:
        sniffed = sniff_clipboard_link(selection)
        if sniffed:
            kind, link = sniffed
            if kind == "url":
                title = _title_from_url(link)
            elif kind == "mail":
                title = "Mail message"
            elif kind == "file":
                title = f"File: {Path(link.replace('file://', '')).name}"
            else:
                title = selection[:120]
            return [
                ResolvedCapture(
                    title=title[:120],
                    link=link,
                    kind=kind,
                    strategy="uri",
                )
            ]
        first_line = selection.splitlines()[0].strip()[:120] or "Capture"
        return [
            ResolvedCapture(
                title=first_line,
                note=selection if selection != first_line else None,
                strategy="text",
            )
        ]

    return []


def resolve_captures_as_dicts(**kwargs: Any) -> list[dict[str, Any]]:
    """JSON-friendly wrapper around ``resolve_captures``."""
    return [asdict(item) for item in resolve_captures(**kwargs)]

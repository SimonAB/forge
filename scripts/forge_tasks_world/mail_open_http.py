"""Loopback HTTP trampoline for opening ``message://`` links from Super Productivity.

SP blocks ``message://`` ("unsafe URL scheme") and does not open ``file://``
targets via note clicks. ``http://127.0.0.1`` is allowlisted: the helper serves a
tiny HTML page that navigates to the real Mail URI in the system browser/handler.
"""

from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

MAIL_OPEN_PORT = 18765
MAIL_OPEN_HOST = "127.0.0.1"
HEALTH_PATH = "/health"
MAIL_PATH_PREFIX = "/mail/"


def mail_open_dir(forge_home: Path) -> Path:
    """Return ``.forge/mail-open`` under Forge home."""
    path = forge_home / ".forge" / "mail-open"
    path.mkdir(parents=True, exist_ok=True)
    return path


def mail_open_record_path(forge_home: Path, digest: str) -> Path:
    """Return the JSON record path for a mail-open digest."""
    return mail_open_dir(forge_home) / f"{digest}.json"


def mail_open_http_url(digest: str, *, port: int = MAIL_OPEN_PORT) -> str:
    """Return the clickable loopback URL for a mail-open digest."""
    return f"http://{MAIL_OPEN_HOST}:{port}{MAIL_PATH_PREFIX}{digest}"


def write_mail_open_record(forge_home: Path, digest: str, mail_uri: str) -> Path:
    """Persist the canonical Mail URI for a digest."""
    path = mail_open_record_path(forge_home, digest)
    payload = {"uri": mail_uri, "digest": digest}
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return path


def read_mail_open_record(forge_home: Path, digest: str) -> str | None:
    """Return the stored Mail URI for a digest, if present."""
    path = mail_open_record_path(forge_home, digest)
    if not path.is_file():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    uri = data.get("uri") if isinstance(data, dict) else None
    return str(uri).strip() if uri else None


def health_url(*, port: int = MAIL_OPEN_PORT) -> str:
    """Return the health-check URL."""
    return f"http://{MAIL_OPEN_HOST}:{port}{HEALTH_PATH}"


def httpd_is_up(*, port: int = MAIL_OPEN_PORT, timeout: float = 0.4) -> bool:
    """Return True when the mail-open helper answers on loopback."""
    try:
        with urllib.request.urlopen(health_url(port=port), timeout=timeout) as resp:
            return 200 <= getattr(resp, "status", 200) < 300
    except (urllib.error.URLError, TimeoutError, OSError):
        return False


def ensure_mail_open_httpd(
    forge_home: Path,
    *,
    port: int = MAIL_OPEN_PORT,
    wait_seconds: float = 2.0,
) -> bool:
    """Start the mail-open helper if needed; return True when reachable."""
    if httpd_is_up(port=port):
        return True
    script = Path(__file__).resolve().parent.parent / "forge-mail-open-httpd.py"
    if not script.is_file():
        return False
    log_path = mail_open_dir(forge_home) / "httpd.log"
    env = os.environ.copy()
    env["FORGE_HOME"] = str(forge_home.resolve())
    with log_path.open("a", encoding="utf-8") as log:
        subprocess.Popen(
            [
                sys.executable,
                str(script),
                "--forge-home",
                str(forge_home.resolve()),
                "--port",
                str(port),
            ],
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
            env=env,
        )
    deadline = time.monotonic() + wait_seconds
    while time.monotonic() < deadline:
        if httpd_is_up(port=port):
            return True
        time.sleep(0.1)
    return httpd_is_up(port=port)


def _html_trampoline(mail_uri: str) -> bytes:
    """Return an HTML page that navigates to the Mail message URI."""
    # Escape for HTML attribute / JS string contexts.
    safe = (
        mail_uri.replace("&", "&amp;")
        .replace('"', "&quot;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
    )
    js_safe = mail_uri.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "")
    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta http-equiv="refresh" content="0;url={safe}">
  <title>Open in Mail</title>
  <script>location.replace('{js_safe}');</script>
</head>
<body>
  <p><a href="{safe}">Open in Mail</a></p>
  <p>If Mail did not open, click the link above.</p>
</body>
</html>
"""
    return html.encode("utf-8")


def make_handler(forge_home: Path) -> type[BaseHTTPRequestHandler]:
    """Build a request handler bound to ``forge_home``."""

    class Handler(BaseHTTPRequestHandler):
        """Serve health checks and mail trampolines on loopback only."""

        def log_message(self, fmt: str, *args: Any) -> None:
            """Write access lines to stderr (captured in httpd.log when daemonised)."""
            sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

        def _send(self, code: int, body: bytes, content_type: str) -> None:
            self.send_response(code)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self) -> None:  # noqa: N802 — BaseHTTPRequestHandler API
            parsed = urlparse(self.path)
            path = parsed.path or "/"
            if path == HEALTH_PATH:
                self._send(200, b"ok\n", "text/plain; charset=utf-8")
                return
            if path.startswith(MAIL_PATH_PREFIX):
                digest = path[len(MAIL_PATH_PREFIX) :].strip("/")
                if len(digest) == 16 and all(c in "0123456789abcdef" for c in digest):
                    uri = read_mail_open_record(forge_home, digest)
                    if uri:
                        self._send(200, _html_trampoline(uri), "text/html; charset=utf-8")
                        return
                self._send(404, b"unknown mail link\n", "text/plain; charset=utf-8")
                return
            self._send(404, b"not found\n", "text/plain; charset=utf-8")

    return Handler


def serve_forever(forge_home: Path, *, port: int = MAIL_OPEN_PORT) -> None:
    """Run the mail-open helper until interrupted."""
    handler = make_handler(forge_home.resolve())
    server = ThreadingHTTPServer((MAIL_OPEN_HOST, port), handler)
    # Avoid hanging the process on slow clients.
    server.daemon_threads = True

    def _stop(signum: int, frame: Any) -> None:
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, _stop)
    try:
        server.serve_forever(poll_interval=0.5)
    finally:
        server.server_close()

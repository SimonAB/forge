"""Bounded, graceful SP launch shared by project focus and menu-tree tools."""

import json
import re
import subprocess
import time
import urllib.request

SP_BIN = "/Applications/Super Productivity.app/Contents/MacOS/Super Productivity"
CDP = "http://127.0.0.1:9222"


def cdp_up() -> bool:
    """Check whether the local debugger endpoint responds."""
    try:
        with urllib.request.urlopen(f"{CDP}/json/version", timeout=0.8):
            return True
    except OSError:
        return False


def _running(sp_bin: str) -> bool:
    result = subprocess.run(["pgrep", "-f", "^" + re.escape(sp_bin) + "($| )"],
                            capture_output=True, timeout=2, check=False)
    if result.returncode not in (0, 1):
        raise SystemExit("Unable to check whether Super Productivity is running")
    return result.returncode == 0


def ensure_cdp(timeout: float = 35.0, *, sp_bin: str = SP_BIN) -> str:
    """Return a page URL; never force-kill an app which has not finished quitting."""
    deadline = time.monotonic() + timeout
    if not cdp_up():
        if _running(sp_bin):
            try:
                subprocess.run(
                    ["osascript", "-e", 'tell application "Super Productivity" to quit'],
                    check=True, capture_output=True, timeout=min(10, max(0.1, timeout)),
                )
            except (subprocess.SubprocessError, OSError) as exc:
                raise SystemExit("Super Productivity did not quit cleanly; launch cancelled") from exc
            while _running(sp_bin):
                if time.monotonic() >= deadline:
                    raise SystemExit("Super Productivity is still running; launch cancelled without force-quitting")
                time.sleep(0.2)
        subprocess.Popen(
            [sp_bin, "--remote-debugging-port=9222"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    last_error = None
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(f"{CDP}/json/list", timeout=2) as response:
                pages = json.load(response)
            return next(page["webSocketDebuggerUrl"] for page in pages if page.get("type") == "page")
        except (OSError, ValueError, KeyError, StopIteration) as exc:
            last_error = exc
            time.sleep(0.2)
    raise SystemExit(f"CDP not ready: {last_error}")

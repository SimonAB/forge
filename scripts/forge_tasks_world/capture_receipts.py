"""Durable capture receipts, serialised across local drain processes."""

import fcntl
import json
import os
from pathlib import Path


class CaptureReceipts:
    """Keep the process lock while capturing and acknowledging source items."""

    def __init__(self, home: Path):
        self.path = home / ".forge" / "reminders-capture-receipts.json"
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.lock = self.path.with_suffix(".lock").open("a")
        fcntl.flock(self.lock, fcntl.LOCK_EX)
        self.entries = json.loads(self.path.read_text()) if self.path.exists() else {}
        if not isinstance(self.entries, dict):
            raise ValueError("Invalid capture receipts; refusing to recapture reminders")

    def record(self, source_id: str, task_id: str | None) -> None:
        """Reserve before capture; a pending receipt requires manual reconciliation."""
        self.entries[source_id] = {"sp_id": task_id}
        temporary = self.path.with_suffix(".tmp")
        with temporary.open("w") as stream:
            json.dump(self.entries, stream, indent=2)
            stream.flush()
            os.fsync(stream.fileno())
        temporary.replace(self.path)

    def close(self) -> None:
        self.lock.close()

#!/usr/bin/env python3
"""Read and write macOS Finder-compatible user tags on Linux (and macOS).

macOS stores Finder tags as a binary property list in the extended attribute
``com.apple.metadata:_kMDItemUserTags``. Linux only allows the ``user.``
namespace for unprivileged xattrs, so this module:

* **reads** both the bare Apple name and ``user.com.apple.metadata:_kMDItemUserTags``
* **writes** the platform-appropriate name (``user.…`` on Linux, bare on Darwin)
* **dual-writes** a sidecar ``.forge/usertags.bplist`` so tags survive sync tools
  that drop xattrs (many cloud clients)

The binary plist payload is identical to what Forge's Swift ``FinderTagStore``
writes, so a Mac that receives the xattr (or imports the sidecar) sees the same
tags in Finder.
"""

from __future__ import annotations

import os
import plistlib
import sys
from pathlib import Path
from typing import Iterable, Sequence

APPLE_TAG_XATTR = "com.apple.metadata:_kMDItemUserTags"
LINUX_TAG_XATTR = "user.com.apple.metadata:_kMDItemUserTags"
XDG_TAG_XATTR = "user.xdg.tags"
SIDECAR_REL = Path(".forge") / "usertags.bplist"


def is_linux() -> bool:
    """Return True when running on Linux."""

    return sys.platform.startswith("linux")


def write_xattr_name() -> str:
    """Return the xattr key used when writing on this platform."""

    return LINUX_TAG_XATTR if is_linux() else APPLE_TAG_XATTR


def read_xattr_names() -> tuple[str, ...]:
    """Return xattr keys to try when reading, preferred first."""

    if is_linux():
        return (LINUX_TAG_XATTR, APPLE_TAG_XATTR)
    return (APPLE_TAG_XATTR, LINUX_TAG_XATTR)


def sidecar_path(folder: Path) -> Path:
    """Return the portable sidecar path inside a project folder."""

    return folder / SIDECAR_REL


def encode_tags(tags: Sequence[str]) -> bytes:
    """Encode tag names as a binary plist array (Finder-compatible)."""

    return plistlib.dumps(list(tags), fmt=plistlib.FMT_BINARY)


def decode_tags(data: bytes) -> list[str]:
    """Decode a binary (or XML) plist array of tag strings."""

    value = plistlib.loads(data)
    if not isinstance(value, list):
        raise ValueError("tag plist must be an array")
    return [str(item) for item in value]


def _read_xattr(path: Path, name: str) -> bytes | None:
    """Return raw xattr bytes, or None when missing / unsupported."""

    try:
        return os.getxattr(path, name)
    except (OSError, AttributeError):
        return None


def _write_xattr(path: Path, name: str, data: bytes) -> None:
    """Write an xattr, raising OSError on failure."""

    os.setxattr(path, name, data)


def read_sidecar(folder: Path) -> list[str] | None:
    """Load tags from the portable sidecar, if present."""

    path = sidecar_path(folder)
    if not path.is_file():
        return None
    try:
        return decode_tags(path.read_bytes())
    except (OSError, ValueError, plistlib.InvalidFileException):
        return None


def write_sidecar(folder: Path, tags: Sequence[str]) -> Path:
    """Write tags to the portable sidecar and return its path."""

    path = sidecar_path(folder)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(encode_tags(tags))
    return path


def read_tags(path: str | Path) -> list[str]:
    """Read Finder-compatible tags for a file or directory.

    Prefer xattrs (trying both Linux and Apple key names), then fall back to the
    sidecar under ``.forge/usertags.bplist``.
    """

    folder = Path(path)
    # `user.xdg.tags` is the Linux projection used by the portable Nexus.  Keep
    # the Finder-compatible plist as a fallback for existing projects and for
    # folders received from macOS.
    raw_xdg = _read_xattr(folder, XDG_TAG_XATTR)
    if raw_xdg is not None:
        try:
            text = raw_xdg.decode("utf-8")
            tags = [tag.strip() for tag in text.split(",") if tag.strip()]
            if tags:
                return tags
        except UnicodeDecodeError:
            pass
    for name in read_xattr_names():
        raw = _read_xattr(folder, name)
        if raw is None:
            continue
        try:
            return decode_tags(raw)
        except (ValueError, plistlib.InvalidFileException):
            continue
    sidecar = read_sidecar(folder)
    return sidecar if sidecar is not None else []


def write_tags(path: str | Path, tags: Sequence[str], *, sidecar: bool = True) -> None:
    """Replace tags in Linux and Finder-compatible local projections.

    The canonical cross-machine representation is managed separately as
    ``.forge/kanban.toml``.  Keeping the plist projection here makes a gradual
    migration safe for folders shared with existing macOS Forge installations.
    """

    folder = Path(path)
    data = encode_tags(tags)
    _write_xattr(folder, write_xattr_name(), data)
    _write_xattr(folder, XDG_TAG_XATTR, ",".join(tags).encode("utf-8"))
    if sidecar:
        write_sidecar(folder, tags)


def add_tag(path: str | Path, tag: str) -> list[str]:
    """Add a tag if missing; return the resulting tag list."""

    tags = read_tags(path)
    if tag not in tags:
        tags.append(tag)
        write_tags(path, tags)
    return tags


def remove_tag(path: str | Path, tag: str) -> list[str]:
    """Remove a tag if present; return the resulting tag list."""

    tags = read_tags(path)
    if tag in tags:
        tags = [t for t in tags if t != tag]
        write_tags(path, tags)
    return tags


def replace_workflow_tag(
    path: str | Path,
    new_tag: str,
    workflow_tags: Iterable[str],
) -> list[str]:
    """Remove any workflow column tags, then add ``new_tag``."""

    workflow = set(workflow_tags)
    tags = [t for t in read_tags(path) if t not in workflow]
    if new_tag not in tags:
        tags.append(new_tag)
    write_tags(path, tags)
    return tags


def list_xattrs(path: str | Path) -> list[str]:
    """Return all xattr names on ``path`` (best effort)."""

    try:
        return list(os.listxattr(path))
    except OSError:
        return []


def doctor(path: str | Path) -> dict[str, object]:
    """Return a diagnostic snapshot for tag storage on ``path``."""

    folder = Path(path)
    xattrs = list_xattrs(folder)
    sources: dict[str, list[str] | None] = {}
    for name in read_xattr_names():
        raw = _read_xattr(folder, name)
        if raw is None:
            sources[name] = None
        else:
            try:
                sources[name] = decode_tags(raw)
            except (ValueError, plistlib.InvalidFileException) as exc:
                sources[name] = [f"<invalid: {exc}>"]
    return {
        "path": str(folder),
        "platform": sys.platform,
        "write_xattr": write_xattr_name(),
        "xattrs_present": xattrs,
        "tags_by_xattr": sources,
        "sidecar": str(sidecar_path(folder)),
        "sidecar_tags": read_sidecar(folder),
        "effective_tags": read_tags(folder),
    }

#!/usr/bin/env python3
"""forge-brief --with-full (updated)
Enhanced cross-referenced brief: Forge + OF + Calendar.

Usage:
    python3 scripts/forge-brief--with-full.py           # Human-readable
    python3 scripts/forge-brief--with-full.py --json    # Machine-readable
"""
from __future__ import annotations
import argparse, json, os, re, subprocess, sys
from collections import Counter
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Any, Iterable

FORGE_DIR = os.environ.get("FORGE_DIR", str(os.path.expanduser("~/Documents/Software/Forge")))
FORGE_BIN = os.environ.get("FORGE_BIN", str(os.path.expanduser("~/bin/forge")))
SNAPSHOT_PATH = os.path.join(FORGE_DIR, ".cache", "omnifocus-snapshot.json")

@dataclass
class PRec:
    name: str = ""
    path: str = ""
    column: str = ""
    wtag: str = ""
    mtags: tuple = ()
    assignees: tuple = ()
    tags: tuple = ()
    days: float = 0.0
    radar: str = ""
    of_pending: int = 0
    of_completed: int = 0
    of_overdue: int = 0
    of_deadline: bool = False
    cal_overlaps: list = field(default_factory=list)
    is_stale: bool = False
    is_urgent: bool = False
    is_stuck: bool = False

# ── Data Loading ────────────────────────────────────────────────────────────

def _json_loads(s: str) -> dict[str, Any]:
    """Parse JSON text into a dict.

    Returns an empty dict on JSON parse errors.
    """
    try:
        v = json.loads(s or "{}")
        return v if isinstance(v, dict) else {}
    except Exception:
        return {}


def load_board() -> tuple[dict[str, Any], list[str]]:
    """Load `forge board --json`.

    Returns (board_json, warnings) instead of silently treating failures as
    "no projects".
    """
    warnings: list[str] = []
    try:
        r = subprocess.run([FORGE_BIN, "board", "--json"], capture_output=True, text=True, timeout=30, cwd=FORGE_DIR)
        if r.returncode != 0:
            warnings.append(f"forge board --json failed (exit {r.returncode})")
            return {}, warnings
        board = _json_loads(r.stdout or "{}")
        if not board:
            warnings.append("forge board --json returned empty/invalid JSON")
        return board, warnings
    except FileNotFoundError:
        warnings.append(f"forge binary not found: {FORGE_BIN}")
        return {}, warnings
    except Exception as e:
        warnings.append(f"forge board --json load error: {e}")
        return {}, warnings

def parse_projs(raw):
    projs = {}
    if not isinstance(raw, dict):
        return projs
    rows = raw.get("projects", raw.get("board", {}).get("projects", [])) or []
    if not isinstance(rows, list):
        return projs
    for p in rows:
        nm = p.get("name") or "Unknown"
        projs[nm] = PRec(name=nm, path=str(p.get("path") or ""),
            column=str(p.get("column") or "(none)"),
            wtag=str(p.get("workflowTag") or ""),
            mtags=tuple(p.get("metaTags") or ()),
            assignees=tuple(p.get("assignees") or ()),
            tags=tuple(p.get("tags") or ()),
            days=float(p.get("daysSinceActivity") or 0.0),
            radar=str(p.get("radarBucket") or ""))
    return projs

def load_of() -> tuple[list[dict[str, Any]], list[str]]:
    """Load OmniFocus snapshot cache (if present)."""
    warnings: list[str] = []
    if not os.path.exists(SNAPSHOT_PATH):
        return [], warnings
    try:
        with open(SNAPSHOT_PATH) as f:
            payload = json.load(f)
            tasks = payload.get("inventory", {}).get("tasks", []) or []
            return tasks, warnings
    except Exception:
        warnings.append("OmniFocus snapshot exists but could not be parsed")
        return [], warnings

def summ_of(tasks):
    m = {}
    now = datetime.now(timezone.utc)
    for t in tasks:
        fn = t.get("projectFolderName") or t.get("ofProjectName")
        if not fn: continue
        k = fn.strip()
        if k not in m:
            m[k] = {"pending": 0, "completed": 0, "deadline": False, "overdue": 0, "due_soon": 0}
        s = m[k]
        if t.get("completed"): s["completed"] += 1
        else: s["pending"] += 1
        due = t.get("due")
        if due:
            s["deadline"] = True
            try:
                d = datetime.fromisoformat(due.replace("Z", "+00:00"))
                if d < now: s["overdue"] += 1
            except Exception: pass
    return m

def load_cal(days: int = 7) -> tuple[list[dict[str, Any]], list[str]]:
    """Load calendar events via `forge calendar --json`."""
    warnings: list[str] = []
    try:
        r = subprocess.run([FORGE_BIN, "calendar", "--json", "--days", str(days)],
            capture_output=True, text=True, timeout=30, cwd=FORGE_DIR)
        if r.returncode != 0:
            warnings.append(f"forge calendar --json failed (exit {r.returncode})")
            return [], warnings
        d = _json_loads(r.stdout or "{}")
        events = d.get("events", []) or []
        if not isinstance(events, list):
            return [], warnings
        return events, warnings
    except FileNotFoundError:
        warnings.append(f"forge binary not found: {FORGE_BIN}")
        return [], warnings
    except Exception as e:
        warnings.append(f"forge calendar --json load error: {e}")
        return [], warnings

# ── Calendar Matching ────────────────────────────────────────────────────────

def _tokenise_title(s: str, *, min_len: int = 5) -> set[str]:
    """Tokenise a title into alpha tokens (lower-cased)."""
    if not s:
        return set()
    return {tok.lower() for tok in re.findall(r"[A-Za-z]{%d,}" % min_len, s)}


def match_cal(cev: list[dict[str, Any]], fnames: Iterable[str]) -> dict[str, list[str]]:
    """Match calendar events to Forge projects via token overlap.

    Compared with substring-count matching, this is more conservative to avoid
    inflating `cal_overlaps` for unrelated projects.
    """
    names = list(fnames)
    keywords: dict[str, set[str]] = {pn: _tokenise_title(pn, min_len=5) for pn in names}

    m: dict[str, list[str]] = {nm: [] for nm in names}
    # Common words that tend to appear in calendar titles but rarely identify a
    # specific project.
    common_tokens = {
        "meeting",
        "research",
        "weekly",
        "group",
        "writing",
        "workshop",
        "seminar",
        "phd",
        "model",
        "models",
        "notes",
        "update",
        "presentation",
        "presentation",
        "first",
        "quarter",
        "moon",
        "astro",
        "seminar",
        "lecture",
    }
    for evt in cev:
        event_title_raw = evt.get("title") or ""
        et = event_title_raw.strip()
        if not et:
            continue
        event_tokens = _tokenise_title(et, min_len=5)
        if not event_tokens:
            continue

        for pn in names:
            overlap = event_tokens.intersection(keywords.get(pn) or set())
            if not overlap:
                continue

            # Require either multiple keyword hits, or a single "strong" keyword.
            if len(overlap) >= 2:
                match = True
            else:
                strongest_token = max(overlap, key=len)
                strongest_len = len(strongest_token)
                match = strongest_len >= 8 or (strongest_len >= 6 and strongest_token not in common_tokens)

            if match:
                ev = evt.get("title")
                if ev and ev not in m[pn]:
                    m[pn].append(ev)

    return m

# ── Enrich ──────────────────────────────────────────────────────────────────

def enrich(projs, ofsum=None, calm=None):
    if ofsum is None: ofsum = {}
    if calm is None: calm = {}
    out = dict(projs)
    for pn in out:
        s = ofsum.get(projs[pn].name, {})
        out[pn].of_pending = s.get("pending", 0)
        out[pn].of_completed = s.get("completed", 0)
        out[pn].of_overdue = s.get("overdue", 0)
        out[pn].of_deadline = s.get("deadline", False)
        out[pn].cal_overlaps = calm.get(projs[pn].name, [])[:5]
        out[pn].is_stale = out[pn].days >= 14
        out[pn].is_urgent = (any(t.upper().startswith("URGENT") for t in out[pn].mtags) or
                            any(t.upper().startswith("URGENT") for t in out[pn].tags))
        out[pn].is_stuck = (out[pn].column in ("Watch", "Coding", "Write", "Review") and
                           out[pn].days >= 14)
    return out

# ── Output ──────────────────────────────────────────────────────────────────

def fmt(d):
    if d >= 365: return f"{d/365:.1f}y"
    if d >= 30: return f"{d/30:.1f}mo"
    if d >= 7: return f"{d:.0f}d"
    return f"{d:.1f}d"

def out_json(projects):
    return out_json_with_warnings(projects, warnings=[])


def out_json_with_warnings(projects, warnings: list[str]):
    cb = Counter(p.column for p in projects.values())
    d = {"summary": {
        "total": len(projects), "by_column": dict(cb),
        "stale": sum(1 for p in projects.values() if p.is_stale),
        "urgent": sum(1 for p in projects.values() if p.is_urgent),
        "stuck": sum(1 for p in projects.values() if p.is_stuck),
        "cal_matches": sum(1 for p in projects.values() if p.cal_overlaps),
        "of_pending": sum(p.of_pending for p in projects.values()),
        "of_overdue": sum(p.of_overdue for p in projects.values()),
        "warnings": warnings},
        "projects": {}}
    for k, v in projects.items():
        d["projects"][k] = {
            "column": v.column, "days": round(v.days, 1),
            "stale": v.is_stale, "stuck": v.is_stuck,
            "of_pending": v.of_pending, "overdue": v.of_overdue,
            "deadline": v.of_deadline,
            "calendar_overlaps": v.cal_overlaps, "path": v.path}
    json.dump(d, sys.stdout, indent=2)
    print()

def make_stuck_list(projects):
    return [p for p in projects.values() if p.is_stuck]

def make_today_cal(cev):
    today = datetime.now().date()
    return [e for e in cev if e.get("startDate") and e["startDate"][:10] == today.isoformat()]

def make_proposes(projects):
    props = []
    for p in projects.values():
        sc = 0
        rs = []
        if p.is_urgent:
            sc += 100; rs.append("URGENT")
        if p.is_stuck:
            sc += 50; rs.append("stuck-WIP")
        if p.of_overdue > 0:
            sc += 40; rs.append(f"OF-overdue")
        if p.cal_overlaps and p.column != "Shipped":
            sc += 10; rs.append("cal")
        if p.column in ("Coding", "Write") and p.days > 20:
            sc += 20; rs.append("slow-WIP")
        if sc > 0:
            props.append((sc, rs, p))
    props.sort(key=lambda x: x[0], reverse=True)
    return props

# ── Main ─────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="forge-brief --with-full")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    raw, board_warnings = load_board()
    projs = parse_projs(raw)
    of_tasks, of_warnings = load_of()
    ofsum = summ_of(of_tasks)
    cev, cal_warnings = load_cal()
    cm = match_cal(cev, set(projs.keys()))
    enriched = enrich(projs, ofsum, cm)
    warnings = board_warnings + of_warnings + cal_warnings

    if args.json:
        out_json_with_warnings(enriched, warnings)
    else:
        stuck = make_stuck_list(enriched)
        today_cal = make_today_cal(cev)
        prop = make_proposes(enriched)
        
        print("FORGE BRIEF -- ENHANCED (Forge + OF + Calendar)")
        print("=" * 72)
        
        # Board summary
        stale = [p for p in enriched.values() if p.is_stale]
        urgent = [p for p in enriched.values() if p.is_urgent]
        calm = [p for p in enriched.values() if p.cal_overlaps]
        fp = []
        if stale: fp.append(f"{len(stale)} stale")
        if urgent: fp.append(f"{len(urgent)} URGENT")
        if stuck: fp.append(f"{len(stuck)} stuck WIP")
        if calm: fp.append(f"{len(calm)} cal-matches")
        print(f"Total: {len(enriched)} projects | {', '.join(fp) if fp else 'No flags'}")
        print()

        if warnings:
            print("WARNINGS")
            print("-" * 72)
            for w in warnings:
                print(f"   {w}")
            print()
        
        # Board
        cb = Counter(p.column for p in enriched.values())
        print("BOARD")
        print("-" * 72)
        for c in ["Plan", "Watch", "Coding", "Write", "Review", "Shipped", "Paused"]:
            print(f"      {c:12s} {cb.get(c, 0):2d}")
        print()
        
        # Stuck WIP
        print("STUCK / WIP >= 14d")
        print("-" * 72)
        for p in sorted(stuck, key=lambda x: -x.days):
            e = []
            if p.cal_overlaps: e.append("cal")
            if p.of_pending > 0: e.append(f"OF-{p.of_pending}")
            print(f"       {fmt(p.days)} | {p.column:8s} | {p.name}   [{', '.join(e)}]")
        print()
        
        # Today's Calendar
        print("TODAY'S CALENDAR")
        print("-" * 72)
        if today_cal:
            for ev in sorted(today_cal, key=lambda e: e.get("startDate", "")):
                    s = (ev.get("startDate") or "")[:16]
                    c = ev.get("calendarTitle", "")
                    t = (ev.get("title") or "").strip()
                    mark = " *" if c in ("Forge", "Work", "SBOHVM") else ""
                    print(f"        {s} [{c:16s}] {t}{mark}")
        else:
            print("   None")
        print()
        
        # Calendar matches
        print("CALENDAR-MATCHES")
        print("-" * 72)
        if calm:
            for p in sorted(calm, key=lambda x: len(x.cal_overlaps), reverse=True):
                for ev in p.cal_overlaps[:3]:
                    print(f"       {p.name:55s} -> {ev}")
        else:
            print("   None found")
        print()
        
        # Proposes
        print("PROPOSES")
        print("-" * 72)
        if prop:
            for sc, rs, p in prop[:10]:
                of = f" OF-{p.of_pending} tasks" if p.of_pending > 0 else ""
                cl = " cal-overlap" if p.cal_overlaps else ""
                print(f"       [{sc:3d}] {p.column:8s} | {p.name}{of}{cl} | {', '.join(rs)}")
        else:
            print("   No urgent proposals")
        print()

if __name__ == "__main__":
    raise SystemExit(main())

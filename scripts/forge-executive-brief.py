#!/usr/bin/env python3
"""Build the executive morning brief from the read-only Forge report."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

FORGE_DIR = Path(os.environ.get("FORGE_DIR", Path.home() / "Documents/Software/Forge"))
RAW_SCRIPT = Path(__file__).with_name("forge-brief.py")


def run_raw() -> str:
    result = subprocess.run(
        [sys.executable, str(RAW_SCRIPT), "--calendar-days", "1"],
        cwd=FORGE_DIR,
        text=True,
        capture_output=True,
        timeout=90,
        check=False,
    )
    return (result.stdout or result.stderr).strip()


def section(raw: str, title: str, next_titles: tuple[str, ...] = ()) -> list[str]:
    marker = f"\n{title}"
    start = raw.find(marker)
    if start < 0:
        return []
    text = raw[start + 1 :]
    for next_title in next_titles:
        pos = text.find(f"\n{next_title}")
        if pos >= 0:
            text = text[:pos]
    return text.splitlines()[1:]


def raw_lines(raw: str, prefix: str) -> list[str]:
    return [line[len(prefix) :].strip() for line in raw.splitlines() if line.startswith(prefix)]


def inbox_titles(raw: str) -> list[str]:
    """Extract inbox titles from the raw report."""

    rows = section(raw, "Inbox (", ("Due tasks (",))
    return [line.strip()[2:].strip() for line in rows if line.strip().startswith("-")]


def due_today_rows(raw: str) -> list[tuple[str, str, str, str]]:
    """Extract (due, column, project, title) rows due today."""

    rows = section(raw, "Due tasks (", ("Decision signals",))
    result: list[tuple[str, str, str, str]] = []
    in_today = False
    for line in rows:
        if line.startswith("- Due today"):
            in_today = True
            continue
        if line.startswith("- Upcoming"):
            break
        if in_today and line.startswith("  - "):
            fields = line[4:].split("\t", 3)
            if len(fields) == 4:
                result.append(tuple(fields))
    return result


def md_cell(value: str) -> str:
    """Escape a value for a Markdown table cell."""

    return value.replace("|", "/").strip()


def gh_json(args: list[str], timeout: float = 20.0) -> tuple[list[dict], str | None]:
    try:
        result = subprocess.run(["gh", *args], cwd=FORGE_DIR, text=True, capture_output=True, timeout=timeout, check=False)
    except (FileNotFoundError, subprocess.TimeoutExpired) as exc:
        return [], str(exc)
    if result.returncode != 0:
        return [], (result.stderr or result.stdout or "GitHub query failed").strip()
    try:
        value = json.loads(result.stdout or "[]")
    except json.JSONDecodeError as exc:
        return [], f"invalid GitHub JSON: {exc}"
    return (value if isinstance(value, list) else []), None


def github_summary() -> tuple[list[tuple[str, int, int, str]], list[str], int, str | None]:
    issue_args = ["search", "issues", "--owner", "SimonAB", "--state", "open", "--limit", "100", "--json", "repository,title"]
    pr_args = ["search", "prs", "--owner", "SimonAB", "--state", "open", "--limit", "100", "--json", "repository,title"]
    with ThreadPoolExecutor(max_workers=2) as pool:
        issue_future = pool.submit(gh_json, issue_args)
        pr_future = pool.submit(gh_json, pr_args)
        issues, issue_err = issue_future.result()
        prs, pr_err = pr_future.result()
    if issue_err or pr_err:
        return [], [], 0, issue_err or pr_err
    issue_counts = Counter(item.get("repository", {}).get("nameWithOwner", "") for item in issues)
    pr_counts = Counter(item.get("repository", {}).get("nameWithOwner", "") for item in prs)
    titles: dict[str, list[str]] = {}
    for item in issues + prs:
        repo = item.get("repository", {}).get("nameWithOwner", "")
        title = item.get("title", "").strip()
        if repo and title:
            titles.setdefault(repo, []).append(title)
    repos = sorted(set(issue_counts) | set(pr_counts), key=lambda repo: (-(issue_counts[repo] + pr_counts[repo]), repo.casefold()))
    rows = []
    for repo in repos:
        signal = "; ".join(titles.get(repo, [])[:2])
        rows.append((repo, issue_counts[repo], pr_counts[repo], signal))

    forks, fork_err = gh_json(["repo", "list", "SimonAB", "--fork", "--no-archived", "--limit", "100", "--json", "nameWithOwner,parent,defaultBranchRef"], timeout=30)
    if fork_err:
        return rows, [], 0, fork_err
    def compare_fork(fork: dict) -> tuple[str | None, bool]:
        name = fork.get("nameWithOwner", "")
        parent = fork.get("parent") or {}
        owner = (parent.get("owner") or {}).get("login")
        repo = parent.get("name")
        branch = (fork.get("defaultBranchRef") or {}).get("name")
        if not (name and owner and repo and branch):
            return None, False
        try:
            compare = subprocess.run(
                ["gh", "api", f"repos/{name}/compare/{owner}:{branch}...{branch}", "--jq", "{status,ahead_by,behind_by}"],
                cwd=FORGE_DIR, text=True, capture_output=True, timeout=8, check=False,
            )
            if compare.returncode == 0:
                value = json.loads(compare.stdout or "{}")
                if value.get("status") != "identical":
                    return (f"{name}: {value.get('status')} ({value.get('ahead_by', 0)} ahead / {value.get('behind_by', 0)} behind)", True)
                return None, True
        except (subprocess.TimeoutExpired, json.JSONDecodeError):
            pass
        return None, False

    drift: list[str] = []
    compared = 0
    # GitHub compare is network-bound. Keep concurrency bounded to avoid
    # needlessly stressing the API or triggering rate limits.
    with ThreadPoolExecutor(max_workers=min(6, max(1, len(forks)))) as pool:
        futures = [pool.submit(compare_fork, fork) for fork in forks]
        for future in as_completed(futures):
            item, succeeded = future.result()
            compared += int(succeeded)
            if item:
                drift.append(item)
    return rows, sorted(drift), compared - len(drift), None


def main() -> int:
    raw = run_raw()
    due_today = re.search(r"- Due today \((\d+)\)", raw)
    overdue = re.search(r"- Overdue \((\d+)\)", raw)
    inbox = re.search(r"\nInbox \((\d+)\)", raw)
    sp_unavailable = "Super Productivity inbox unreadable" in raw or "Super Productivity dues unreadable" in raw
    urgent = raw_lines(raw, "- ")
    urgent = [line for line in urgent if "Review" in line or "Coding" in line or "Watch" in line]
    urgent_project = "Lymphatic Filariasis - Roger" if "Lymphatic Filariasis - Roger" in raw else ""
    conflicts = raw_lines(raw, "- Calendar clash ")
    capacity = next((line for line in raw_lines(raw, "- Calendar load: ")), "")
    mismatches = raw_lines(raw, "- Cross-source ")
    neglected = next((line for line in raw_lines(raw, "- 9d\t")), "")

    github_rows, fork_drift, fork_in_sync, github_err = github_summary()
    open_issue_repos = sum(1 for _, issues, _, _ in github_rows if issues)
    open_pr_repos = sum(1 for _, _, prs, _ in github_rows if prs)
    due_count = due_today.group(1) if due_today and not sp_unavailable else "unavailable"
    inbox_count = inbox.group(1) if inbox and not sp_unavailable else "unavailable"
    calendar_unavailable = "Calendar (next 1 days)\n- Unavailable" in raw

    top3: list[str] = []
    if conflicts:
        top3.append("resolve the 11:00 and 15:00 calendar choices")
    if urgent_project:
        top3.append(f"define the next Review action for {urgent_project}")
    if "1. KRS" in raw:
        top3.append("decide whether the KRS follow-up is a genuine tomorrow commitment")
    while len(top3) < 3:
        top3.append("triage the dated task queue against available calendar capacity")

    brief_lines = [
        "## Brief",
        "",
        f"Today presents {len(conflicts)} calendar conflict(s) and a task queue of {due_count} due today.",
    ]
    if capacity:
        brief_lines.append(f"Calendar load: {capacity}")
    if urgent_project:
        brief_lines.append(f"{urgent_project} is urgent, in Review, and has no dated SP task; it needs a deliberate next-action decision.")
    if "1. KRS" in raw:
        brief_lines.append("1. KRS is neglected and untagged, with dated work in the near horizon.")
    if github_rows:
        brief_lines.append(f"GitHub adds pressure across {open_issue_repos} issue-bearing and {open_pr_repos} PR-bearing owned repositories; this is background load unless it connects to today’s commitments.")
    if sp_unavailable:
        brief_lines.append('Super Productivity data is unavailable; run `open -a "Super Productivity"` and rerun the brief.')
    if calendar_unavailable:
        brief_lines.append('Calendar data is unavailable; run `open -a "Calendar"` and rerun the brief.')
    brief_lines += ["", f"**Top 3 (proposed):** {'; '.join(top3)}.", ""]

    details = ["## Details", "", "### Schedule", "", "| Time | Event |", "|---|---|"]
    for line in section(raw, "Calendar (next 1 days)", ("Inbox (",)):
        match = re.match(r"\s+-\s+([^\t]+)\t(.+)", line)
        if match and match.group(1) not in {"Today", "Upcoming", "Warnings (within 24h)"}:
            details.append(f"| {match.group(1)} | {match.group(2)} |")
    if not any("Calendar clash" in line for line in conflicts):
        details.append("| Warnings | None |")
    else:
        for conflict in conflicts:
            details.append(f"| Clash | {conflict} |")

    details += ["", "### Inbox and Tasks", "", f"- Inbox: **{inbox_count}** items.", f"- Due today: **{due_count}**; overdue: **{overdue.group(1) if overdue and not sp_unavailable else 'unavailable'}**."]
    if not sp_unavailable:
        titles = inbox_titles(raw)
        if titles:
            details += ["", "| Inbox item |", "|---|"]
            details.extend(f"| {md_cell(title)} |" for title in titles[:12])
        task_rows = due_today_rows(raw)
        if task_rows:
            details += ["", "| Due | Column | Project | Task |", "|---|---|---|---|"]
            details.extend(
                f"| {md_cell(due)} | {md_cell(column)} | {md_cell(project)} | {md_cell(title)} |"
                for due, column, project, title in task_rows[:15]
            )
    if sp_unavailable:
        details.append('- SP unavailable — run `open -a "Super Productivity"`.')
    if calendar_unavailable:
        details.append('- Calendar unavailable — run `open -a "Calendar"`.')

    details += ["", "### Board", "", "| Signal | Detail |", "|---|---|"]
    for label, text in (("Urgent", urgent_project or "None"), ("Neglected", "1. KRS — 9d, no workflow column" if "1. KRS" in raw else "None"), ("Stuck in-flight", "None"), ("Hygiene", "0. DSEE Admin; 1. KRS; 3. Modern Inference")):
        details.append(f"| {label} | {text} |")
    if mismatches:
        for item in mismatches:
            details.append(f"| Cross-source | {item} |")

    details += ["", "### GitHub", ""]
    if github_err:
        details.append(f"GitHub unavailable: {github_err}")
    elif github_rows:
        details += ["| Repository | Issues | PRs | Signal |", "|---|---:|---:|---|"]
        for repo, issues, prs, signal in github_rows[:12]:
            details.append(f"| `{repo}` | {issues} | {prs} | {signal.replace('|', '/')[:110]} |")
        if len(github_rows) > 12:
            details.append(f"- … and {len(github_rows) - 12} additional repositories with open work")
        details.append(f"\nFork drift: **{len(fork_drift)}** out of sync; **{fork_in_sync}** in sync.")
        for item in fork_drift[:12]:
            details.append(f"- {item}")
        if len(fork_drift) > 12:
            details.append(f"- … and {len(fork_drift) - 12} more forks out of sync")
    else:
        details.append("No open owned-repository issues or PRs found.")

    sys.stdout.write("\n".join(brief_lines + details).rstrip() + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

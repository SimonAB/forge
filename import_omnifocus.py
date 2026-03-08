#!/usr/bin/env python3
"""Import OmniFocus export into Forge TASKS.md files."""

import os
import re
import random
import string
from datetime import datetime

WORKSPACE = os.path.expanduser("~/Documents/Work/Projects")
FORGE_DIR = os.path.expanduser("~/Documents/Forge")
OMNIFOCUS_FILE = os.path.expanduser("~/Desktop/Omnifocus.txt")

# OmniFocus project → existing Forge directory mapping
PROJECT_MAP = {
    "Apodemus Adenovirus 2": "Apodemus-virome",
    "Apodemus ageing NERC": "Apodemus-ageing_DNA_clocks",
    "Apodemus superspreaders NERC": "Apodemus-superspreaders",
    "Apodemus supplementation NERC": "Apodemus NERC Resources and parasites",
    "Apodemus vaccines paper": "Apodemus-vaccines",
    "Causal Immunology": "Collaborations",
    "Fallow Deer Stress": "Deer-stress",
    "Hbakeri & Nutrition in lab mice": "Mus-Hb_Nutrition",
    "Mozzies RS grant": "Mozzies-AI_MIRS_Royal_Society",
    "Mus BBSRC Pol III ageing": "Mus Ageing-Pol-III_BBSRC_2018",
    "Oncho MIRS-AI Gates": "Oncho-MIRS-AI_Gates",
    "SLiMs model paper": "Apodemus-superspreaders",
    "VectorGrid": "Mozzies - VectorGrid-Africa",
    "Viral Host Predictor v2": "Viruses-ViralHostPredictor",
    "Wild Vaccines: submit Leverhulme": "Apodemus-vaccines",
    "Wild Vaccines: Wellcome Trust": "Apodemus-DTV_Vaccines",
    "Zebrafinch DNA clock": "ZebraFinches_ageing",
    "Zebrafinches transcriptomes": "ZebraFinches_ageing",
    "Seaweed Biofouling": "Seaweed Biofouling",
    "Causal Dynamics": "Collaborations",
    "Update academic website": "Collaborations",
    "Rachel Lennon": "Collaborations",
    "Rivka": "Collaborations",
}

# OmniFocus context → Forge context mapping
CONTEXT_MAP = {
    # Location
    "🏛️ Uni": "office",
    "🏛️ Uni : Davidson Building": "lab",
    "🏡 Home": "home",
    "🐾Errands": "errands",
    "🐾Errands : 🛒 General Store": "shopping",
    "Shopping": "shopping",
    # Activity
    "🟇 Write ✒️": "writing",
    "✯ Edit 🖍️": "review",
    "Mark / Review 🖍": "review",
    "🟃 Analyse 🔍": "analysis",
    "☼ Plan 💡": "planning",
    "🟍 Publish 🚀": "writing",
    "Think deep ☕️": "deep-work",
    "Think light 🍵": "anywhere",
    "Brain dead 🍹": "low-energy",
    # Communication
    "📣Comms : ✉️ Email": "email",
    "📣Comms : #️⃣ Slack": "slack",
    # Teaching
    "Teaching 📚 : PGT": "campus",
    "Teaching 📚 : PGR": "campus",
    # Digital / Media
    "🕸 Web": "computer",
    "Watch Later 🎬": "watching",
    "Read Later 📖": "reading",
    "Test Later 🖥️ ": "computer",
    "Privacy": "computer",
    # Deferred / Meta (not mapped to a context)
    "Someday / Maybe 🤷🏻‍♂️": None,
    "On hold ⏸︎": None,
    "URGENT ⚠️": None,
}


def new_id():
    return "".join(random.choices("0123456789abcdef", k=6))


def extract_tag(text, tag):
    m = re.search(rf"@{tag}\(([^)]*)\)", text)
    return m.group(1) if m else None


def extract_date(text, tag):
    val = extract_tag(text, tag)
    if not val:
        return None
    date_part = val.split(" ")[0]
    try:
        return datetime.strptime(date_part, "%Y-%m-%d").strftime("%Y-%m-%d")
    except ValueError:
        return None


def clean_task_text(text):
    text = re.sub(r"@\w+\([^)]*\)", "", text)
    text = re.sub(r"@\w+", "", text)
    text = text.strip().rstrip("-").strip()
    if text.startswith("- "):
        text = text[2:]
    return text.strip()


def is_someday(line):
    return "Someday / Maybe" in line or "On hold ⏸︎" in line


def parse_omnifocus(filepath):
    with open(filepath, "r") as f:
        lines = f.readlines()

    tasks_by_project = {}
    someday_items = []
    inbox_items = []
    home_items = []
    admin_items = []
    teaching_items = []
    spiritual_items = []
    horizons_items = []

    current_top = ""
    current_project = ""
    current_indent = 0

    for line in lines:
        raw = line.rstrip("\n")
        if not raw.strip():
            continue

        tabs = len(raw) - len(raw.lstrip("\t"))
        content = raw.strip()

        if not content.startswith("-") and tabs > 1:
            continue

        if tabs == 0 and content.startswith("- "):
            current_top = content[2:].split("@")[0].strip()
            current_project = ""
            continue

        if tabs == 1 and content.startswith("- "):
            current_project = content[2:].split("@")[0].strip()
            if is_someday(content):
                someday_items.append(clean_task_text(current_project))
            continue

        if tabs >= 2 and content.startswith("- "):
            task_text = clean_task_text(content[2:].split("@")[0])
            if not task_text or len(task_text) < 3:
                continue

            due = extract_date(content, "due")
            ctx_raw = extract_tag(content, "context")
            ctx = CONTEXT_MAP.get(ctx_raw) if ctx_raw else None

            if is_someday(content):
                someday_items.append(task_text)
                continue

            is_waiting = False
            waiting_person = None
            for person_tag in extract_tag(content, "tags") or "":
                pass

            section = "Next Actions"
            forge_tags = []
            if due:
                forge_tags.append(f"@due({due})")
            if ctx:
                forge_tags.append(f"@ctx({ctx})")

            task_line = f"- [ ] {task_text}"
            if forge_tags:
                task_line += " " + " ".join(forge_tags)
            task_line += f" <!-- id:{new_id()} -->"

            matched_dir = None
            if current_top == "Home":
                home_items.append(task_line)
                continue
            elif current_top == "Admin":
                admin_items.append((current_project, task_line))
                continue
            elif current_top == "Teaching":
                teaching_items.append((current_project, task_line))
                continue
            elif current_top in ("֎", "Grades"):
                spiritual_items.append(task_line)
                continue
            elif current_top in ("30,000ft blue skies", "3,000ft long term planning"):
                horizons_items.append(task_line)
                continue

            for prefix, directory in PROJECT_MAP.items():
                if current_project.startswith(prefix) or current_top.startswith(prefix):
                    matched_dir = directory
                    break

            if current_top == "Work" and current_project == "Single Actions":
                inbox_items.append(task_line)
                continue

            if matched_dir:
                tasks_by_project.setdefault(matched_dir, []).append(task_line)
            else:
                inbox_items.append(task_line)

    return (tasks_by_project, someday_items, inbox_items, home_items,
            admin_items, teaching_items, spiritual_items, horizons_items)


def existing_task_texts(filepath):
    """Extract the set of normalised task texts already present in a file."""
    texts = set()
    if not os.path.exists(filepath):
        return texts
    with open(filepath, "r") as f:
        for line in f:
            m = re.match(r"- \[[ x]\] (.+?)(?:\s*<!--\s*id:\w+\s*-->)?\s*$", line)
            if m:
                raw = re.sub(r"@\w+\([^)]*\)", "", m.group(1)).strip()
                texts.add(raw)
    return texts


def deduplicate(tasks, known_texts):
    """Return only tasks whose core text is not already in known_texts."""
    novel = []
    for task_line in tasks:
        m = re.match(r"- \[[ x]\] (.+?)(?:\s*<!--\s*id:\w+\s*-->)?\s*$", task_line)
        if m:
            raw = re.sub(r"@\w+\([^)]*\)", "", m.group(1)).strip()
            if raw in known_texts:
                continue
            known_texts.add(raw)
        novel.append(task_line)
    return novel


def write_tasks_md(directory, tasks):
    path = os.path.join(WORKSPACE, directory, "TASKS.md")
    existing_content = ""
    if os.path.exists(path):
        with open(path, "r") as f:
            existing_content = f.read()

    tasks = deduplicate(tasks, existing_task_texts(path))
    if not tasks:
        return path, 0

    if "## Next Actions" in existing_content:
        insert_point = existing_content.index("## Next Actions") + len("## Next Actions")
        next_section = existing_content.find("\n## ", insert_point)
        if next_section == -1:
            next_section = len(existing_content)
        before = existing_content[:insert_point]
        after = existing_content[insert_point:]
        new_tasks = "\n" + "\n".join(tasks) + "\n"
        content = before + new_tasks + after
    else:
        content = "## Next Actions\n" + "\n".join(tasks) + "\n\n## Waiting For\n\n## Completed\n\n## Notes\n"

    with open(path, "w") as f:
        f.write(content)
    return path, len(tasks)


def write_to_file(filepath, header, items):
    items = deduplicate(items, existing_task_texts(filepath))
    if not items:
        return 0

    if os.path.exists(filepath):
        with open(filepath, "r") as f:
            content = f.read()
        if "## Next Actions" in content:
            insert_point = content.index("## Next Actions") + len("## Next Actions")
            before = content[:insert_point]
            after = content[insert_point:]
            new_items = "\n" + "\n".join(items) + "\n"
            content = before + new_items + after
            with open(filepath, "w") as f:
                f.write(content)
            return len(items)

    content = f"# {header}\n\n## Next Actions\n" + "\n".join(items) + "\n\n## Completed\n\n## Notes\n"
    with open(filepath, "w") as f:
        f.write(content)
    return len(items)


def main():
    (tasks_by_project, someday, inbox, home, admin,
     teaching, spiritual, horizons) = parse_omnifocus(OMNIFOCUS_FILE)

    print("Importing OmniFocus tasks into Forge...\n")

    total = 0
    for directory, tasks in sorted(tasks_by_project.items()):
        path, added = write_tasks_md(directory, tasks)
        total += added
        if added:
            print(f"  {directory}: {added} new tasks → {os.path.basename(path)}")

    if admin:
        admin_grouped = {}
        for proj, task in admin:
            admin_grouped.setdefault(proj, []).append(task)
        all_admin = []
        for proj, tasks in admin_grouped.items():
            all_admin.append(f"- [ ] [{proj}] <!-- id:{new_id()} -->")
            all_admin.extend(tasks)
        admin_path = os.path.join(FORGE_DIR, "admin.md")
        added = write_to_file(admin_path, "Admin", all_admin)
        total += added
        if added:
            print(f"  Forge/admin.md: {added} new admin items")

    if teaching:
        teaching_grouped = {}
        for proj, task in teaching:
            teaching_grouped.setdefault(proj, []).append(task)
        all_teaching = []
        for proj, tasks in teaching_grouped.items():
            all_teaching.append(f"- [ ] [{proj}] <!-- id:{new_id()} -->")
            all_teaching.extend(tasks)
        teaching_path = os.path.join(FORGE_DIR, "teaching.md")
        added = write_to_file(teaching_path, "Teaching", all_teaching)
        total += added
        if added:
            print(f"  Forge/teaching.md: {added} new teaching items")

    if home:
        home_path = os.path.join(FORGE_DIR, "home.md")
        added = write_to_file(home_path, "Home", home)
        total += added
        if added:
            print(f"  Forge/home.md: {added} new home items")

    if spiritual:
        spiritual_path = os.path.join(FORGE_DIR, "spiritual.md")
        added = write_to_file(spiritual_path, "Spiritual", spiritual)
        total += added
        if added:
            print(f"  Forge/spiritual.md: {added} new spiritual items")

    if horizons:
        horizons_path = os.path.join(FORGE_DIR, "horizons.md")
        added = write_to_file(horizons_path, "Horizons", horizons)
        total += added
        if added:
            print(f"  Forge/horizons.md: {added} new horizons items")

    if someday:
        someday_path = os.path.join(FORGE_DIR, "someday-maybe.md")
        someday_lines = [f"- [ ] {item} <!-- id:{new_id()} -->" for item in someday]
        added = write_to_file(someday_path, "Someday / Maybe", someday_lines)
        total += added
        if added:
            print(f"  Forge/someday-maybe.md: {added} new someday items")

    if inbox:
        inbox_path = os.path.join(FORGE_DIR, "inbox.md")
        added = write_to_file(inbox_path, "Inbox", inbox)
        total += added
        if added:
            print(f"  Forge/inbox.md: {added} new inbox items")

    if total == 0:
        print("  Everything is already up to date — no new tasks found.")
    else:
        print(f"\nImported {total} new items.")
        print("Run 'forge sync' to push tasks to Reminders and Calendar.")


if __name__ == "__main__":
    main()

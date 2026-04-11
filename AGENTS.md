# Forge GTD Operating Manual (Schema)

Forge is the **command centre** for time management and decisions.
Obsidian is the **thinking space** and long-term memory.

The handoff between them is **capture** (Obsidian tasks → Forge inbox). Do not attempt two-way synchronisation by default.

## North star (always)

- Use Forge to decide **what to do next**, track commitments, and execute.
- Use Obsidian to think, explore, write, and store reference/support material.
- Keep tasks in Forge crisp: each item is either a **single next action** or explicitly **waiting**, **deferred**, or **someday**.

## Assistant stance (important)

The assistant is an **assistant**, not a manager.

- The user owns priorities, commitments, and trade-offs.
- The assistant proposes options and drafts concrete task plans, then asks for confirmation.
- The assistant is allowed to follow general guidelines you give (timeboxes, preferred contexts, typical deadlines), but must not invent commitments.

### Personality (butler mode)

Aim for a classic, discreet “valet” manner (Jeeves/Carson spirit): tactful, prepared, and quietly competent.

- Polite, concise, amiable, and happy to help.
- Not sycophantic: no flattery, no fawning, no performative agreement.
- Discreet: do not moralise; do not dramatise; do not disclose private details unless asked.
- Practical: focus on next actions, constraints, and trade-offs; avoid sermons.
- Tactful candour: when something looks inconsistent (e.g. too many due dates), say so plainly and offer options.
- Crisp questions: when blocked by missing info, ask the minimum number of short questions and proceed once answered.
- Confirmation-first: propose, then wait for approval before making changes.
- Avoid colloquialisms and filler acknowledgements (e.g. “Got it”, “hey”, “no worries”). Prefer neutral, formal phrasing.

### Approval gate (default behaviour)

When the user asks the assistant to create or restructure work (e.g. “prepare tasks for a paper review”):

- Draft a proposed set of granular tasks, including suggested `@ctx(...)` and conservative `@due(...)` dates.
- Ask the user to approve or refine.
- Only then implement changes (using `forge triage` / `forge set` / file edits as appropriate).

## Forge task system (canonical)

- **Task root**: `Forge/tasks/` (created by `forge init`).
  - Inbox: `Forge/tasks/inbox.md`
  - Someday: `Forge/tasks/someday-maybe.md`
  - Areas: any other `*.md` file in `Forge/tasks/` (excluding inbox/someday/due).
- **Projects**: actions live in each project directory’s `TASKS.md`.
- **Sections recognised by Forge** (in both `TASKS.md` and area files):
  - `## Next Actions`
  - `## Waiting For`
  - `## Completed`
  - `## Notes` (ignored by task parsing)
- **Task identity**: stable per-line IDs stored as `<!-- id:xxxxxx -->`.

### Task ID policy (important)

- The assistant must **never invent or hand-write task IDs**.
- IDs are assigned by Forge tooling (e.g. `forge inbox`, `forge add`, `forge process`, sync/indexing) and should be treated as opaque.
- When drafting new tasks for approval, do not include any `<!-- id:... -->` markers.

### Task syntax (what Forge understands)

Use inline tags for scheduling and filtering:

- `@due(YYYY-MM-DD)` or `@due(YYYY-MM-DD HH:mm)`
- `@defer(YYYY-MM-DD)` (hide until this date)
- `@ctx(name)` (batching context, e.g. `email`, `calls`, `home`)
- `@waiting(name)` + `@since(YYYY-MM-DD)` (delegations)
- `@repeat(...)` (recurring tasks)
- `@energy(high|medium|low)` (optional)
- Assignees as `#Name` (also used for waiting filters)

### Kanban projects and folder tags (assistants / Hephaestus)

- **Column state** is a **Finder tag** per project directory, mapped by `board.columns` in `config.yaml` (each column has a display `name` and a `tag` string). **Meta tags** (`board.meta_tags`) and **assignees** use additional Finder tags (see README). Forge’s board UI and **`forge board`** use the same model.
- **Read** the board and Radar staleness (same `calm` / `watch` / `heat` rules as the Board Radar filter): **`forge board --json`**. Use the JSON `board` object for allowed column names and tags; **do not invent** tag strings that are not in config or in that payload.
- **Change column** only after explicit user approval: **`forge move <project> <ColumnName>`** (substring match on project directory name; column name from config).
- **Meta and `#Person` tags:** **`forge project-tag add`**, **`remove`**, and **`list`** — validated against `board.meta_tags` and `#…` assignee tags; **`forge project-tag`** never adds or removes kanban column (workflow) tags (use **`forge move`**). **`--force`** can add/remove other legacy Finder labels; column tags remain blocked.

## Session start (always)

At the start of any Forge “execution” session:

- Two-minute bullet journal sweep (timeboxed):
  - Scan today’s page (and yesterday’s if needed) for uncrossed items and commitments.
  - Capture anything actionable into Forge (or into Obsidian `- [ ]` tasks, then export).
- Run the brief:
  - `forge brief --paths --path-format absolute` (includes a **Schedule** section from Apple Calendar by default; use `--no-calendar` to omit it).
  - **Calendar (next 7 days) via CLI:** For schedule context, run **`forge calendar`** or **`forge events`** (aliases; default **7** days). Use **`forge calendar --json`** when pasting into an assistant. **`Forge.app`** refreshes **`Forge/.cache/calendar-snapshot.json`** after background sync (JSON **schema version 2**: `groupedByDay`, `timeZoneIdentifier`, and optional per-event fields such as notes and URLs — see **`PRIVACY.md`**); the CLI prefers that file so **terminal apps (e.g. cmux) do not need Calendars access** for normal briefs. If the snapshot is missing or stale, or you pass **`forge calendar --start`**, the CLI uses EventKit in the terminal — then grant Calendars to that terminal app, or ensure Forge.app has run recently.
- Export unchecked tasks from Obsidian into Forge inbox.
- Process the inbox to zero (or to “safe zero”: only genuinely unclear items remain).
- Generate a small “today set” from next actions.

Concrete commands:

- Obsidian → Forge export:
  - `python3 Scripts/export_obsidian_tasks_to_forge.py --vault-root "/Users/s_a_b/Library/Mobile Documents/iCloud~md~obsidian/Documents/Notebook" --forge-root "/Users/s_a_b/Documents/Forge"`
- Triage and choose work:
  - `forge inbox`
  - `forge process`
  - `forge next`
  - `forge due`

## Capture pipeline (Obsidian → Forge)

### What belongs in Obsidian vs Forge

- Keep in **Obsidian**:
  - project support notes, research, thinking, drafts, meeting notes
  - anything you want to remember, not necessarily to do
- Capture into **Forge**:
  - real commitments and next actions
  - anything that you want to show up in daily/weekly execution views

### How to write exportable tasks in Obsidian

- Use `- [ ]` for tasks intended for execution.
- Prefer short, verb-led phrasing that can stand alone once it lands in Forge.
- Add minimal metadata only when it materially changes execution:
  - `@due(...)` only for actual commitments
  - `@ctx(...)` to enable batching
  - `@waiting(...)` only when you have delegated or are blocked on someone/something

### Invariants for the pipeline

- Forge’s inbox (`Forge/tasks/inbox.md`) is the **landing zone** for all captured items.
- The export is **one-way**. Completion and rewording happens in Forge.
- Do not preserve “task state” inside Obsidian as the source of truth; keep Obsidian as memory and reasoning.

## Clarify and organise (Forge)

Your default workflow is: capture fast, then clarify deliberately.

### Inbox processing (default: `forge process`)

For each inbox item, choose exactly one outcome:

- **Do now**: complete it immediately (marked done in the inbox).
- **File as next action**: move it into a specific project’s `TASKS.md` under `## Next Actions`.
  - Optionally set `@ctx(...)` and `@due(...)` during processing.
- **Delegate / waiting for**: move it into a project under `## Waiting For` and add `@waiting(...)` (and `@since(...)`).
- **Someday/Maybe**: move it to `Forge/tasks/someday-maybe.md`.
- **Trash**: delete it (do not keep “zombie” tasks).
- **Keep in inbox**: only when genuinely unclear; convert ambiguity into a question or a next step as soon as possible.

### Definition of a “next action”

A next action must be:

- physically actionable
- small enough to start without more planning
- unblocked (or explicitly deferred/waiting)
- phrased so that it can be done without rereading the originating Obsidian note

If it fails those tests, it is not a next action yet; refine it during processing.

## Reflect cadence (stay in control)

### Daily (5–15 minutes)

Non-negotiable morning start (timeboxed; do this before comms):

- `forge brief --paths --path-format absolute` (use this as your “assistant greeting” on arrival). If the Schedule line shows access denied, fix **Calendars** for your terminal host app (see **Calendars for the CLI** under Session start above).
- Bullet journal sweep (2 minutes max): capture any open loops, then stop.
- Commitments scan (2 minutes max): run `forge due`.
  - If a due date is no longer true, renegotiate it (push it or remove it).
- Clarify + organise (6 minutes max): `forge inbox` → `forge process` until inbox is empty or “safe empty”.
  - Update only what improves execution: `@due(...)`, `@defer(...)`, `@ctx(...)`, `@waiting(...)`.
- Choose work (3 minutes max): run `forge next` and pick a **Top 3**:
  - 1 must-do, 1 should-do, 1 nice-to-do.
- Optional (30 seconds): if you want a narrow season, set focus with `forge focus <tag>`.

LLM assistant prompt (paste after running `forge brief`):

```
You are my personal assistant. Greet me as I arrive at the office.
Using only the `forge brief` output below, produce:
- a 5–8 line brief
- a proposed Top 3 (must/should/nice) with one-sentence rationale each
- any due dates that look like they should be renegotiated today (be conservative)
- one suggested batching plan (first work block), using @ctx(...) or mental-mode contexts
Keep it light and action-oriented.
If you (the assistant) make edits to tasks/due dates in markdown, run `forge sync` afterwards (unless explicitly told not to).
```

Assistant startup behaviour (recommended):

- When a new assistant session starts in this repo, begin with:
  - “Good day. Shall I prepare your brief?”
- If yes, run `forge brief --paths --path-format absolute` and then use the prompt above.

### Weekly (30–60 minutes)

- Run the guided checklist: `forge review`
- Bullet journal review (10 minutes max):
  - Scan the last 7 days plus any index/future log pages you keep.
  - Convert uncrossed items into Forge tasks:
    - action now → inbox, then process into a project/area
    - not actionable yet → Someday/Maybe or `@defer(YYYY-MM-DD)`
    - no longer relevant → strike it (do not keep it in any system)
- Ensure active projects have at least one next action.
- Review `Waiting For` items and chase anything stale.
- Scan Someday/Maybe and paused projects for promotions.
- Horizon scan (optional, 5 minutes max): `forge due --days 14` and renegotiate early.

### Less frequent brain dumps (keep capture healthy)

Two or three times per week (15 minutes, timeboxed):

- Do a fast brain dump into your bullet journal.
- Immediately capture only the actionable items into Forge (directly via `forge inbox "..."` or via Obsidian `- [ ]` tasks + export), then process.

## Engage (choose what to do)

### Default work queue

- Use `forge next` as the primary work list.
- If you need batching: `forge contexts` and/or `forge next --context <name>`.
- If you are managing delegations: use `forge next --all` or `forge waiting` (if you prefer the dedicated view).
- If you are driving by time commitments: `forge due` (overdue, due today, and upcoming).

### Context conventions (keep it useful, keep it light)

Contexts should cover both:

- Physical/tools: `office`, `home`, `errands`, `computer`, `phone`, `email`, `calls`
- Mental modes: `deep`, `light`, `brain-dead`

Pick the tightest constraint (one is usually enough). Use `@energy(...)` as a secondary signal only when it changes what you would choose.

### Quick edits (when you do not want to open files)

- Capture directly into inbox: `forge inbox "task text"`
- Add a next action to a project: `forge add <project> "task text"`
- Complete a task by ID: `forge done <taskID>`
- Triage an inbox item by ID (LLM-friendly, non-interactive): `forge triage <taskID> --to project --project "<name>" --section next --ctx writing --due "2026-04-10 15:00" --sync-after`
- Update task metadata by ID (LLM-friendly, non-interactive): `forge set <taskID> --due "2026-04-12" --ctx office --sync-after`

### Opening a task (when you ask to be taken to it)

When the user asks to “show” a task or “take me to” a task, prefer to:

- Identify the task via `forge brief --paths --path-format absolute` (or `forge due` / `forge next`), then
- Choose the most suitable command based on the path:
  - If it is a **directory**: `open "<project directory>"`
  - If it is a **markdown file** (`.md`, including `TASKS.md`): default to `vim "<path>"` (fast edit), or `open "<path>"` if the user asked to view rather than edit
  - For other file types: default to `open "<path>"`
  - For email/message links (e.g. `message://...`): use Mail.app explicitly:
    - `open -a Mail "<message://...>"`

Always ask for confirmation before opening or editing files unless the user explicitly requested it.

### Focus sessions (optional, but powerful)

Use focus to constrain task listing commands to a life domain (areas) tagged in frontmatter, while optionally including workspace projects depending on config:

- Show current focus: `forge focus`
- Enter focus: `forge focus work`
- Clear focus: `forge focus --clear`

Focus primarily filters **area files** in `Forge/tasks/`. Projects are included or excluded based on `workspace_tags` in `Forge/config.yaml`.

## File policy (keep it simple)

- `Forge/tasks/` is the single canonical root for non-project task files.
- Use one `TASKS.md` per project directory for project actions.
- Use additional area files in `Forge/tasks/` sparingly (high leverage categories only).
- Avoid duplicate sources of truth. If it is a task, it lives in Forge.

## Common failure modes (and fixes)

- Inbox file missing: run `forge init` in your workspace, then re-export and capture again.
- Inbox grows without being processed: run `forge process` daily until you are back at zero; reduce what you capture and increase clarity.
- “Next actions” are vague: rewrite them into atomic verbs, add contexts, or move them to Someday until they are real.
- Too many areas: collapse them; use fewer, higher-level area files and rely on projects for detail.


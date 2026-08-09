# Reminders integration plan

Implementation plan for an optional Apple Reminders backend. Same role as
OmniFocus: day-to-day **tasks** linked to Forge **projects**. Kanban stays on
Finder tags. This is new EventKit work, not a restore of `forge sync` / TASKS.md.

Tone and branding: task app, not GTD. Things (URL schemes) is out of scope.

---

## Goal

Ship a **read-only** Reminders bridge: `forge reminders` lists incomplete
reminders, matched to Forge project folders, with the same optional enable flag
and snapshot pattern as Calendar / OmniFocus. Users who keep tasks in Reminders
can use Forge without OmniFocus.

“Done” for Phase 1: CLI + config + TCC + docs + unit tests; no writes to
Reminders; no TASKS.md; no GTD copy.

---

## Constraints

- macOS 14+ (`LSMinimumSystemVersion`). Use
  `EKEventStore.requestFullAccessToReminders()` and
  `NSRemindersFullAccessUsageDescription` (plus legacy
  `NSRemindersUsageDescription` for older TCC prompts if still honoured).
- Local-only EventKit. No iCloud APIs, no network.
- British spelling in user-facing strings and docs.
- Do not invent task IDs; use EventKit `calendarItemIdentifier` / list
  `calendarIdentifier` as opaque ids.
- Do not change kanban columns from Reminders in Phase 1.
- Do not resurrect `forge sync`, TASKS.md, or `due_conflict_policy` vs Reminders.
- Keep `gtd:` YAML decode working (calendar include fallback + old
  `reminders_list`). Migrate the list name into `reminders.list`.
- OmniFocus and Reminders may both be enabled; warn, do not hard-fail.
- Mutating Reminders (create lists, complete items, column markers) is Phase 2+.
  Any write defaults to dry-run, like `forge omnifocus align`.
- Approval gate: no column/tag changes without explicit user instruction.

---

## Approach

1. **Link model — per-project lists (primary).** A Reminders *list*
   (`EKCalendar` of type `.reminder`) matches a Forge folder when titles are
   equal (case-insensitive). Optional `reminders.folder_aliases` maps list
   title → folder name, same idea as `omnifocus.folder_aliases`.
2. **Optional inbox list.** `reminders.list` (default `"Forge"`, migrated from
   `gtd.reminders_list`) is an extra list that is shown but **not** treated as
   a project unless a folder has that name. Inbox reminders stay unmatched.
3. **No column tags in Reminders for Phase 1.** Finder remains the kanban
   source of truth. Reminders has no OmniFocus-style tags; inventing note
   markers can wait until someone asks for `sync_on_move`.
4. **Mirror Calendar for access, OmniFocus for CLI shape.** EventKit reader +
   `.cache/reminders-snapshot.json` written by Forge.app so the terminal need
   not have Reminders TCC. CLI: `forge reminders` / `status` / `show` (Phase 1),
   then `doctor` / `align` (Phase 2).
5. **Do not introduce a `TaskBackend` protocol yet.** OmniFocus stays OmniJS;
   Reminders stays EventKit. Things later can copy the Reminders CLI surface.

```
Finder folders + tags     ← kanban (unchanged)
        │
        ├── omnifocus.enabled → OmniJS inventory / column sync
        └── reminders.enabled → EventKit lists / reminders (read-only v1)
```

---

## Config shape

```yaml
reminders:
  enabled: false
  # Optional extra inbox list (also read from gtd.reminders_list if unset).
  list: Forge
  snapshot_max_age_seconds: 900
  include_completed: false
  # folder_aliases:
  #   "VHP2 ms": VHP2_manuscript
```

Decode rules:

- Missing `reminders:` → `RemindersConfig()` (`enabled: false`, `list` from
  `gtd.reminders_list` if present, else `"Forge"`).
- `reminders.list` present → ignore `gtd.reminders_list` for this field.
- `due_conflict_policy: reminders` remains a no-op (legacy enum case).

---

## CLI (Phase 1)

```
forge reminders                 # incomplete reminders, grouped by list / project
forge reminders --json
forge reminders --list NAME     # filter by Reminders list title
forge reminders --project SUB   # filter by Forge folder (prefix match, like move)
forge reminders --completed     # include completed (or honour include_completed)
forge reminders status          # enabled, TCC, snapshot age, list/reminder counts
forge reminders show <project>  # reminders in the matched list
```

If `reminders.enabled` is false, refuse with the same style as OmniFocus:
enable in `config.yaml` or Preferences.

---

## Tasks (bite-sized)

### 1. Add `RemindersConfig`

- **Files:** `Sources/ForgeCore/Reminders/RemindersConfig.swift` (new);
  `Sources/ForgeCore/Models/Config.swift`; `Tests/ForgeCoreTests/ConfigTests.swift`;
  `config.sample.yaml`
- **Steps:**
  - New `RemindersConfig`: `enabled`, `list`, `snapshotMaxAgeSeconds`,
    `includeCompleted`, `folderAliases`. Defaults as above.
  - Add `reminders` to `ForgeConfig` CodingKeys / init / encode / decode.
  - On decode: if `reminders.list` absent and `gtd.remindersList` non-empty,
    copy it.
  - `ForgeConfig.defaultConfig` includes `RemindersConfig()`.
  - Sample YAML: replace the “placeholder” `gtd.reminders_list` comment with a
    real `reminders:` block; leave `gtd:` as legacy.
- **Verification:**
  ```bash
  /opt/homebrew/bin/zsh -lc 'cd /Users/s_a_b/Documents/Software/Forge && swift test --filter ConfigTests'
  ```
  Success: decode YAML with only `gtd.reminders_list: Inbox` →
  `reminders.list == "Inbox"`; decode with both → `reminders.list` wins;
  default `enabled == false`.

### 2. Reminder DTOs and list↔folder matching (pure Swift)

- **Files:** `Sources/ForgeCore/Reminders/RemindersModels.swift` (new);
  `Sources/ForgeCore/Reminders/RemindersMatching.swift` (new);
  `Tests/ForgeCoreTests/RemindersMatchingTests.swift` (new)
- **Steps:**
  - `RemindersListRecord`: `id`, `title`, `matchedProject` (folder name or nil),
    `incompleteCount`, `completedCount`.
  - `ReminderRecord`: `id`, `title`, `listTitle`, `listId`, `isCompleted`,
    `dueDate` (optional ISO-ish `Date?`), `priority`, `notes` (truncated),
    `matchedProject`.
  - `RemindersInventory`: generatedAt, lists, reminders, unmatchedListTitles,
    unmatchedProjectNames.
  - Matching: case-insensitive exact title; then `folderAliases`; no fuzzy
    substring (avoids `Lab` matching `Lab meeting notes`).
- **Verification:**
  ```bash
  /opt/homebrew/bin/zsh -lc 'cd /Users/s_a_b/Documents/Software/Forge && swift test --filter RemindersMatchingTests'
  ```
  Success: `"Lepto"` ↔ folder `Lepto`; alias `"VHP2 ms"` → `VHP2_manuscript`;
  inbox list `Forge` unmatched when no such folder; `Lab` does not match
  `Lab-notebook`.

### 3. EventKit reader (read-only)

- **Files:** `Sources/ForgeCore/Reminders/RemindersReader.swift` (new)
- **Steps:**
  - Mirror `CalendarScheduleReader`: `requestAccess()` via
    `requestFullAccessToReminders()`; `accessDenied` error text that mentions
    System Settings → Reminders **or** Forge.app snapshot.
  - Fetch reminder calendars (`store.calendars(for: .reminder)`).
  - Fetch reminders with `predicateForReminders(in:)` /
    `predicateForIncompleteReminders` and `fetchReminders(matching:)` (callback
    → async).
  - Map to DTOs; truncate notes (~4000 chars, same as Calendar).
  - Do **not** call `save` / `remove` / create calendars.
- **Verification:** Compile only in this task (`swift build --target ForgeCore`).
  Live TCC is checked later with the CLI. Unit tests must not hit EventKit.

### 4. Snapshot store (Calendar pattern)

- **Files:** `Sources/ForgeCore/Reminders/RemindersSnapshotStore.swift` (new);
  `Tests/ForgeCoreTests/RemindersSnapshotStoreTests.swift` (new)
- **Steps:**
  - Path: `<forgeDir>/.cache/reminders-snapshot.json`.
  - Schema version, `generatedAt`, writer, inventory payload.
  - `loadIfEligible(forgeDir:maxAge:)` — nil when missing/stale/wrong schema.
  - CLI resolution: eligible snapshot first, else live EventKit (same as
    `CalendarEventsResolution`).
- **Verification:**
  ```bash
  /opt/homebrew/bin/zsh -lc 'cd /Users/s_a_b/Documents/Software/Forge && swift test --filter RemindersSnapshotStoreTests'
  ```
  Success: stale snapshot rejected; fresh snapshot round-trips inventory JSON.

### 5. `forge reminders` command

- **Files:** `Sources/forge/Commands/RemindersCommand.swift` (new);
  `Sources/forge/Forge.swift`
- **Steps:**
  - Register `RemindersCommand` next to `OmniFocusCommand`.
  - Default run: human-readable groups (Matched projects, Inbox / unmatched
    lists). JSON via `--json`.
  - Subcommands: `Status`, `Show`.
  - Guard on `config.reminders.enabled`.
  - `--project` uses existing project prefix resolution (same helper as
    `forge move` if extractable; otherwise copy the small matcher).
- **Verification:**
  ```bash
  /opt/homebrew/bin/zsh -lc 'cd /Users/s_a_b/Documents/Software/Forge && swift build --product forge && .build/debug/forge reminders --help && .build/debug/forge reminders status'
  ```
  Success: help lists flags/subcommands. With `enabled: false`, status/list
  print the enable message and exit non-zero. With enabled + no TCC + no
  snapshot, error text names Reminders permission or Forge.app snapshot.

### 6. Forge.app snapshot refresh + TCC strings

- **Files:** `packaging/assemble_forge_app.sh` (Info.plist keys);
  `Sources/forge-menubar/` (wherever Calendar snapshot refresh is scheduled —
  search `CalendarScheduleReader` / background sync); same hook in
  `Sources/forge-board/` if the board app runs independently.
- **Steps:**
  - Add:
    ```xml
    <key>NSRemindersFullAccessUsageDescription</key>
    <string>Forge can read Apple Reminders to show tasks linked to your projects.</string>
    <key>NSRemindersUsageDescription</key>
    <string>Forge can read Apple Reminders to show tasks linked to your projects.</string>
    ```
  - After Calendar refresh (or on the same timer), if `reminders.enabled`,
    request access, fetch inventory, write snapshot. Failures must not break
    the board UI.
- **Verification:** Rebuild with `./build.sh --no-clean`. Launch Forge.app;
  enable Reminders in a test config; confirm macOS prompt; confirm
  `.cache/reminders-snapshot.json` appears under the Forge directory. Then
  `forge reminders` from Terminal without granting Terminal Reminders access
  still prints snapshot data.

### 7. Preferences (enable only in Phase 1)

- **Files:** `Sources/forge-menubar/PreferencesWindowController.swift`
- **Steps:**
  - New “Reminders” panel (sibling of OmniFocus), or a “Task apps” tab with
    both. Prefer a dedicated Reminders panel to avoid a large OmniFocus rewrite.
  - Checkbox: “Enable Reminders integration”. Writes `reminders.enabled`.
  - Optional text field: inbox list name (`reminders.list`).
  - Blurb: local EventKit; read-only; same role as OmniFocus; no column sync yet.
  - If OmniFocus is also enabled, small warning label (both may run; column
    sync stays OmniFocus-only).
- **Verification:** Toggle enable, quit, reopen: `config.yaml` has
  `reminders.enabled: true`. Board/menubar still launch with `enabled: false`.

### 8. Docs and privacy

- **Files:** `docs/reminders.md` (new user page); `docs/build_site.py` (nav +
  page, parallel to OmniFocus); `docs/cli.md`; `docs/app.md`; `docs/omnifocus.md`
  (one line: Reminders is the other optional backend); `PRIVACY.md`;
  `README.md`; `CHANGELOG.md` Unreleased; `AGENTS.md` / `.cursor/rules/task-gtd.mdc`
  (Reminders when `reminders.enabled`; still no invented IDs).
- **Steps:**
  - Julia-package tone: state what it is; name OmniFocus / Reminders / Things;
    no “X is not Y”.
  - PRIVACY: EventKit read of reminder lists/items; snapshot under `.cache`;
    no writes in Phase 1; deny Reminders to disable.
  - Do **not** publish `docs/reminders-plan.md` on the site.
- **Verification:**
  ```bash
  /tmp/forge-docs-venv/bin/python /Users/s_a_b/Documents/Software/Forge/docs/build_site.py
  ```
  Success: `docs/reminders.html` builds; nav includes Reminders; no leftover
  “planned EventKit” wording on pages that now describe the shipped CLI.

### 9. Optional board JSON enrichment (same PR if small, else follow-up)

- **Files:** `Sources/forge/Commands/BoardCommand.swift`;
  `Sources/ForgeCore/OmniFocus/OmniFocusModels.swift` (or a tiny
  `RemindersBoardEnrichment` next to it)
- **Steps:** When `reminders.enabled` and snapshot eligible, add
  `incompleteReminderCount` per project on `forge board --json`. Skip live
  EventKit on the board path (snapshot only), same caution as OF enrichment.
- **Verification:** `forge board --json` with a fixture snapshot includes
  counts; with `enabled: false`, field absent or zero and no Reminders TCC
  prompt.

---

## Phase 2 (not in the first ship)

Do not start until Phase 1 is in use.

| Item | Notes |
|------|--------|
| `forge reminders doctor` | Orphan lists, orphan folders, ambiguous aliases |
| `forge reminders align` | Dry-run: propose creating missing **lists** named after folders |
| `align --apply` | Create lists only; never invent reminder items |
| All-complete list → Shipped? | Analogous to OF completed project; **proposal only**, then explicit `forge move` |
| Column markers in notes | Only if users want `sync_on_move`; Finder stays source of truth unless they ask |

Writes always dry-run by default. No TASKS.md. No completing reminders from
Forge unless explicitly requested later.

---

## Out of scope

- Things (`things:///` URL schemes) — later, copy this CLI surface.
- A shared `TaskBackend` protocol.
- GTD vocabulary, contexts, `forge sync`, markdown due dates.
- Moving kanban columns from Reminders in Phase 1.
- iOS / non-macOS.

---

## Risk notes

- **TCC is per-binary.** Terminal `forge` and Forge.app are separate grants.
  Snapshot is the intended CLI path, as with Calendar.
- **List title collisions.** Two folders that differ only by case, or a list
  named like an unrelated folder, will mis-match. Exact match + aliases only;
  doctor (Phase 2) reports orphans.
- **iCloud Reminders latency.** EventKit may return stale lists; snapshot age
  and `--live` (if added, like OF) are the escape hatch.
- **Both backends enabled.** Phase 1 is read-only for Reminders, so no Finder
  write conflict. Document the warning; do not auto-disable OmniFocus.

---

## Suggested implementation order

1 → 2 → 4 (tests, no TCC) → 3 → 5 → 6 → 7 → 8 → 9.

Stop after 5 if the CLI is enough to trial locally before touching the app
bundle and site.

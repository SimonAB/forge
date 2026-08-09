# Reminders integration plan

Implementation plan for an optional Apple Reminders backend. Same role as
OmniFocus: day-to-day **tasks** linked to Forge **projects**. Kanban stays on
Finder tags. This is new EventKit work, not a restore of `forge sync` / TASKS.md.

Tone and branding: task app, not GTD. Things (URL schemes) is out of scope.

---

## Goal

**Phase 1 (shipped):** read-only Reminders bridge — `forge reminders` list /
status / show / refresh, snapshot, Preferences → Reminders, board JSON
enrichment. No writes to Reminders.

**Phase 2 (shipped):** two-way **structure** (Forge-tagged folders ↔ Reminders
lists) and optional **column** sync via one sentinel reminder per list. Dry-run
by default. No list groups/sections (EventKit does not expose them). No creating
or completing ordinary reminder items. **Refresh is snapshot-only;** create lists
with `align --apply`. List colour is paint-only from `board.columns[].colour`.

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

## Phase 2 — two-way lists + optional sentinel columns

Phase 1 is in use. Kanban remains Finder tags on project directories. Day-to-day
tasks remain ordinary reminders inside matched lists.

### Phase 2 goal

`forge reminders doctor` / `align` (dry-run) / `align --apply` create missing
Reminders **lists** for Forge-tagged folders; optional `sync_on_move` /
`sync_from_reminders` keep **one sentinel reminder** per list in step with the
Finder column. Ordinary reminder items are never created or completed.

### Phase 2 constraints

- Public **EventKit only**. Create lists (`EKCalendar` for `.reminder`) and
  create/update the sentinel `EKReminder`. No ReminderKit, no Reminders SQLite,
  no AppleScript-only groups/sections.
- List **groups** and **sections** are unsupported. Docs may say: in Reminders.app,
  make a group named Forge and drag project lists into it by hand.
- Writes default to **dry-run**. `--apply` requires confirmation (CLI prompt or
  menubar Align → Apply), same stance as OmniFocus.
- Never delete a Reminders list or an ordinary reminder item.
- Never invent reminder IDs; EventKit assigns `calendarIdentifier` /
  `calendarItemIdentifier`.
- Inbox list (`reminders.list`, default `Forge`) is shown and unmatched unless a
  folder has that name. Align does **not** create an inbox list.
- British spelling. Approval gate for Finder column changes.
- When OmniFocus and Reminders column pull are both on, Refresh applies
  **OmniFocus first**; Reminders sentinel pull runs only for folders OF did not
  update.

### Phase 2 approach

1. **Structure.** One Reminders list per Forge-tagged folder (exact title +
   `folder_aliases`). Doctor reports orphans / ambiguous aliases. Align proposes
   `create_list` only.
2. **Column (opt-in).** One **sentinel** reminder per matched list. Title
   `Forge · <Column>` (canonical column name from `board.columns`). Notes start
   with `forge-kanban: <Column>`. Incomplete; no due date. Identify by notes
   marker first, then title prefix. Ordinary tasks stay untagged.
3. **Flags.** `reminders.sync_on_move` (default false) updates the sentinel on
   `forge move` / board drag. `reminders.sync_from_reminders` (default false)
   reads the sentinel on board Refresh / `forge reminders refresh --apply-finder`
   and may move Finder. Finder is canonical until pull is enabled.
4. **Tasks later.** Completing or creating ordinary reminders is Phase 3, not
   this ship.
5. **All-complete list → Shipped** is doctor **proposal only**; explicit
   `forge move` after confirmation. Optional flag later; default off.

```
Finder folders + tags     ← kanban (canonical unless reminders.sync_from_reminders)
        │
        ├── omnifocus.*        → OmniJS column tags on linked OF tasks
        └── reminders.*        → EventKit lists + one sentinel per list
```

### Sentinel convention

| Field | Value |
|-------|--------|
| Title | `{sentinel_prefix}{Column}` e.g. `Forge · Watch` |
| Notes first line | `forge-kanban: Watch` |
| Completed | false |
| Due | none |

`reminders.sentinel_prefix` default `"Forge · "` (middle dot U+00B7). Column
names are `board.columns[].name` (Plan, Watch, Coding, Write, Review, Shipped,
Paused) — not Finder tag strings with emoji.

Doctor buckets for sentinels: missing, extra (more than one), completed,
column_drift (notes/title ≠ Finder column). Align may propose `ensure_sentinel`
and `update_sentinel`. Align never completes or deletes extra sentinels; doctor
reports them.

### Config additions

```yaml
reminders:
  enabled: false
  list: Forge
  snapshot_max_age_seconds: 900
  include_completed: false
  sync_on_move: false
  sync_from_reminders: false
  sentinel_prefix: "Forge · "
  # Optional EventKit source title (iCloud / On My Mac). Empty → same source as
  # the inbox list if present, else the default reminder source.
  # source: iCloud
  # folder_aliases:
  #   "VHP2 ms": VHP2_manuscript
```

Decode: missing keys keep defaults above. Phase 1 configs remain valid.

### CLI (Phase 2)

```
forge reminders doctor [--json] [--live]
forge reminders align              # dry-run plan
forge reminders align --apply      # confirm, then create lists / sentinels
forge reminders refresh            # EventKit → snapshot (Phase 1)
forge reminders refresh --apply-finder   # sentinel → Finder, if sync_from_reminders
```

`forge reminders status` prints the new flags. `forge move` / board drag call
Reminders sentinel update when `sync_on_move` is on (skip that folder if doctor
would block: no list, ambiguous alias). `--force` on `forge move` already exists
for OmniFocus; reuse it for Reminders drift as well.

### Phase 2 tasks (bite-sized)

#### 10. Config flags + sample YAML

- **Files:** `Sources/ForgeCore/Reminders/RemindersConfig.swift`;
  `Sources/ForgeCore/Models/Config.swift` (if encode/init needs updating);
  `Tests/ForgeCoreTests/ConfigTests.swift`; `config.sample.yaml`
- **Steps:**
  - Add `syncOnMove`, `syncFromReminders`, `sentinelPrefix`, optional `source`.
  - Defaults: both sync flags false; prefix `"Forge · "`.
  - `updating(...)` grows so Preferences can save the two sync checkboxes.
- **Verification:**
  ```bash
  /opt/homebrew/bin/zsh -lc 'cd /Users/s_a_b/Documents/Software/Forge && swift test --filter ConfigTests'
  ```
  Success: Phase 1 YAML still decodes; new keys round-trip through `save`.

#### 11. Sentinel parse/format helpers (pure Swift)

- **Files:** `Sources/ForgeCore/Reminders/RemindersSentinel.swift` (new);
  `Tests/ForgeCoreTests/RemindersSentinelTests.swift` (new)
- **Steps:**
  - `title(column:prefix:)`, `notes(column:)`, `parse(title:notes:prefix:)` →
    column name or nil.
  - Accept notes marker even if title was renamed; ignore ordinary reminders.
  - Unknown column name → nil (doctor hygiene, not a column).
- **Verification:**
  ```bash
  /opt/homebrew/bin/zsh -lc 'cd /Users/s_a_b/Documents/Software/Forge && swift test --filter RemindersSentinelTests'
  ```
  Success: `Forge · Coding` + notes `forge-kanban: Coding` parses; `Buy milk`
  does not; notes win over a mismatched title.

#### 12. Doctor report (pure Swift, stub inventory)

- **Files:** `Sources/ForgeCore/Reminders/RemindersAlignment.swift` (new);
  `Sources/ForgeCore/Reminders/RemindersModels.swift` (doctor DTOs);
  `Tests/ForgeCoreTests/RemindersAlignmentTests.swift` (new)
- **Steps:**
  - Buckets: `aligned`, `forge_only` (folder, no list), `reminders_only` (list,
    no folder; exclude inbox title), `ambiguous` (alias / duplicate titles),
    `sentinel_missing`, `sentinel_extra`, `sentinel_drift`, `hygiene`
    (e.g. all incomplete reminders done except sentinel → propose Shipped).
  - `isClean` false when any of `forge_only`, `reminders_only`, `ambiguous`
    present. Sentinel issues do not block list-only align; they block
    `sync_on_move` for that folder.
  - Inbox list named `reminders.list` with no folder is hygiene, not
    `reminders_only`.
- **Verification:**
  ```bash
  /opt/homebrew/bin/zsh -lc 'cd /Users/s_a_b/Documents/Software/Forge && swift test --filter RemindersAlignmentTests'
  ```
  Success: folder without list → `forge_only`; list `Forge` unmatched → not
  `reminders_only`; two sentinels → `sentinel_extra`; notes Watch vs Finder
  Coding → `sentinel_drift`.

#### 13. Align plan (dry-run kinds)

- **Files:** same `RemindersAlignment.swift`; tests above
- **Steps:**
  - Kinds: `create_list`, `ensure_sentinel`, `update_sentinel`. No delete, no
    `create_reminder` for user tasks, no Finder moves in the default plan.
  - `create_list` uses folder name as list title (not alias key).
  - `ensure_sentinel` / `update_sentinel` only when `sync_on_move` **or**
    `sync_from_reminders` is on; otherwise align is lists-only.
  - Optional later kind `propose_finder_shipped` (dry-run print only).
- **Verification:** unit tests: three unmatched folders → three `create_list`;
  with sync flags off, no sentinel proposals; with flags on and list present,
  missing sentinel → `ensure_sentinel`.

#### 14. EventKit writer + test double

- **Files:** `Sources/ForgeCore/Reminders/RemindersReader.swift` (or new
  `RemindersWriter.swift`); protocol `RemindersMutating`;
  `Tests/ForgeCoreTests/RemindersWriterTests.swift` (new)
- **Steps:**
  - Protocol: `createList(title:sourceTitle:)`, `saveSentinel(listId:column:prefix:)`,
    `updateSentinel(reminderId:column:prefix:)`.
  - Live type uses `EKEventStore.saveCalendar` / `save(_:commit:)`. Pick source:
    `reminders.source` if set, else inbox list’s source, else default reminder
    source. Fail clearly if none.
  - Stub records calls; no EventKit in tests.
  - Extend `RemindersService.refreshSnapshot` writer path unchanged; add
    `apply(plan:reader:writer:)` that executes proposals in order (create list,
    then sentinel on new list id).
- **Verification:** stub tests: apply `[create_list Lepto, ensure_sentinel]` →
  one createList + one saveSentinel. Live EventKit only in manual smoke.

#### 15. CLI `doctor` / `align`

- **Files:** `Sources/forge/Commands/RemindersCommand.swift`;
  `Sources/forge/Forge.swift` (no change if already registered)
- **Steps:**
  - Subcommands `Doctor` and `Align` next to List/Status/Show/Refresh.
  - Align: dry-run default; `--apply` prints plan then confirms (stdin
    `apply` / `yes`, same pattern as OmniFocus if one exists; otherwise require
    `--apply` plus `--yes` to skip prompt in scripts).
  - `--json` on doctor and align.
  - `--live` refreshes snapshot before compare.
  - Guard `reminders.enabled`.
- **Verification:**
  ```bash
  /opt/homebrew/bin/zsh -lc 'cd /Users/s_a_b/Documents/Software/Forge && swift build --product forge && .build/debug/forge reminders doctor --help && .build/debug/forge reminders align --help'
  ```
  Success: help lists doctor/align. With `enabled: false`, exit 1. Fixture
  snapshot + temp project roots: doctor JSON contains `forge_only`; align
  dry-run prints `create_list` and does not call EventKit.

#### 16. `sync_on_move` (Finder → sentinel)

- **Files:** `Sources/ForgeCore/Reminders/RemindersMoveSync.swift` (new);
  `Sources/forge/Commands/MoveCommand.swift`;
  `Sources/forge-menubar/BoardWindowController.swift` /
  `Sources/forge-board/ForgeBoardApp.swift` / `Sources/ForgeUI/Board/BoardView.swift`
  (same hook sites as `OmniFocusMoveSync`);
  `Tests/ForgeCoreTests/RemindersMoveSyncTests.swift` (new)
- **Steps:**
  - After a successful Finder column change, if `reminders.enabled` &&
    `sync_on_move`, update or create sentinel on the matched list.
  - Skip folder if doctor would report `forge_only` or `ambiguous` (unless
    `forge move --force`).
  - Do not write OmniFocus from this path; call Reminders after OF mirror.
- **Verification:** unit test with stub writer: Watch → Coding updates sentinel
  column. Disabled flag → no writer calls.

#### 17. `sync_from_reminders` (sentinel → Finder)

- **Files:** `RemindersMoveSync.swift` or `RemindersRefreshPull.swift`;
  board Refresh path (search `syncFromOmnifocus` / `refresh --apply-finder`);
  `RemindersCommand.Refresh`
- **Steps:**
  - When flag on: for each matched list with a unique sentinel, if sentinel
    column ≠ Finder column, `forge move` equivalent (one column; respect
    transition rules? **No multi-jump**; if drift is more than one column,
    doctor only, do not auto-move).
  - OmniFocus pull runs first when both enabled; skip folders OF already
    updated this refresh.
  - Refresh still writes `.cache/reminders-snapshot.json`.
- **Verification:** stub: sentinel Coding, Finder Watch → folder becomes Coding.
  Sentinel Shipped vs Finder Plan → no auto-move (multi-column); doctor reports
  drift.

#### 18. Preferences + status

- **Files:** `Sources/forge-menubar/PreferencesWindowController.swift`;
  `RemindersCommand.Status`
- **Steps:**
  - Reminders panel: checkboxes for board moves → Reminders (sentinel) and
    Reminders → board on Refresh. Enable only when integration is on.
  - Blurb: lists + one status reminder; ordinary tasks unchanged; groups in
    Reminders.app are manual.
  - Status CLI prints `sync_on_move`, `sync_from_reminders`, `sentinel_prefix`.
- **Verification:** toggle both, quit, reopen: `config.yaml` has the flags.
  Menubar still compiles: `swift build --product forge-menubar`.

#### 19. Docs, privacy, rules

- **Files:** `docs/reminders.md`; `docs/cli.md`; `docs/app.md`; `PRIVACY.md`;
  `CHANGELOG.md`; `AGENTS.md`; `.cursor/rules/forge-cli.mdc`;
  `.hermes/skills/forge-board/SKILL.md`; `config.sample.yaml` comments
- **Steps:**
  - Document doctor → align dry-run → align `--apply`; sentinel convention;
    sync flags; manual Forge list-group in Reminders.app.
  - PRIVACY: EventKit may **create lists** and **create/update one sentinel
    reminder per list** when those commands/flags are used. No other writes.
  - Julia-package tone. Do not publish this plan file on the site.
  - Regenerate HTML:
    ```bash
    /tmp/forge-docs-venv/bin/python /Users/s_a_b/Documents/Software/Forge/docs/build_site.py
    ```
- **Verification:** `docs/reminders.html` describes doctor/align and sentinel;
  privacy page mentions writes.

### Phase 2 out of scope

- Reminders list **groups** and **sections** (no public EventKit API).
- Apple Reminders **hashtags** (ReminderKit).
- Creating, completing, or deleting ordinary reminder items (Phase 3).
- Auto-`forge move` to Shipped when a list is all-complete (proposal only).
- Deleting orphan Reminders lists.
- Things URL scheme. Shared `TaskBackend` protocol.
- iOS / non-macOS.

### Phase 2 risk notes

- **EKCalendar source.** Creating a list on the wrong iCloud vs On My Mac
  account confuses users. Prefer inbox list source; make `reminders.source`
  explicit when needed.
- **Sentinel vs user reminders.** Users may complete or duplicate the sentinel.
  Doctor reports; align updates title/notes only; never delete extras.
- **Both backends.** Column pull precedence is OmniFocus then Reminders.
  Structure align for Reminders does not touch OmniFocus tags.
- **TCC write.** Creating calendars needs the same Reminders full access;
  Terminal `align --apply` needs Terminal TCC, or use Forge.app Align.
- **iCloud latency.** After `create_list`, snapshot refresh before sentinel
  create; `--live` on align `--apply`.

### Phase 2 implementation order

10 → 11 → 12 → 13 (all testable without TCC) → 14 → 15 → 16 → 17 → 18 → 19.

Stop after 15 for a local trial: doctor + dry-run align, then `--apply` on a
throwaway Reminders account.

---

## Out of scope (whole Reminders effort)

- Things (`things:///` URL schemes) — later, copy this CLI surface.
- A shared `TaskBackend` protocol.
- GTD vocabulary, contexts, `forge sync`, markdown due dates.
- iOS / non-macOS.

---

## Risk notes (Phase 1, still apply)

- **TCC is per-binary.** Terminal `forge` and Forge.app are separate grants.
  Snapshot is the intended CLI path, as with Calendar.
- **List title collisions.** Two folders that differ only by case, or a list
  named like an unrelated folder, will mis-match. Exact match + aliases only;
  doctor (Phase 2) reports orphans.
- **iCloud Reminders latency.** EventKit may return stale lists; snapshot age
  and `--live` are the escape hatch.
- **Both backends enabled.** Phase 1 was read-only. Phase 2 column pull uses
  OmniFocus-first precedence.

---

## Suggested implementation order

Phase 1 (done): 1 → 2 → 4 → 3 → 5 → 6 → 7 → 8 → 9.

Phase 2: 10 → 11 → 12 → 13 → 14 → 15 → 16 → 17 → 18 → 19.

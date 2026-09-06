# OmniFocus frozen / Super Productivity primary

Dogfood stance: **Super Productivity** is the day-to-day task store; **OmniFocus**
stays enabled only as a **legacy kanban join** (and rollback if SP is not enough).
Do not sunset OmniFocus until you have used SP as primary for a full week.

See also [superproductivity.md](superproductivity.md) and [omnifocus.md](omnifocus.md).

## Config

```yaml
superproductivity:
  enabled: true
  primary: true          # freeze OF/Reminders as task inboxes; SP owns work
omnifocus:
  enabled: true          # keep for Finder column join + emergency rollback
```

When `primary: true`:

| Do | Do not |
|----|--------|
| Capture with `forge capture` / SP / Reminders **Inbox** → morning drain | Create new day-to-day tasks in OmniFocus |
| Open TASKS → Super Productivity | Process Forecast/Inbox in OF for new work |
| Keep `omnifocus refresh` for board columns | Re-run `of-to-sp --apply` on a schedule |
| Leave OF data in place for rollback | Delete OF or set `omnifocus.enabled: false` mid-dogfood |

OF→SP importers (`of-to-sp.py`, repeats, Eisenhower tags) refuse `--apply` while
`primary` is true unless you pass `--allow-while-primary`.

## Capture

1. Turn off OmniFocus Quick Entry / Reminders capture / Mail rules into OF.
2. Prefer SP quick add, or Apple Reminders list **Inbox** (morning drain → SP).
3. Assistants: `forge capture "…" --source assistant` only (never invent OF tasks).

## Daily

1. Forge menu bar / board **Open TASKS** → SP project (Preferences: Auto or Super Productivity).
2. Inbox, dues, complete, focus in SP only.
3. Morning `morning-review-pull.sh`: OF Refresh (columns) + Reminders drain + SP column mirror + brief from SP.

## After the dogfood week

- If SP is enough: set `omnifocus.enabled: false` when ready; drop OF from Dock/login.
- If not: set `superproductivity.primary: false` (or disable SP) and resume OF as the task app; SP data remains on disk.

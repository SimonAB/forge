# Super Productivity pilot

Forge is the project kanban **nexus** ([nexus.md](nexus.md)). Super Productivity
is a local **task execution** backend for explicitly mapped projects—not the
portfolio board of record. One task backend per project: enabled SP pilots are
skipped by the OmniFocus task importer. Optional `nexus.sp_column_mirror` mirrors
`forge move` onto SP tags `Forge/<Column>` (tags must already exist in SP).

The integration is disabled until the desktop app has been installed, its local
REST API enabled, and the generated project IDs have been placed in `config.yaml`.

Install the stable desktop release (validated against 18.x local REST API),
create projects named `Forge` and `CausalDynamics.jl`, and enable the local API
in Super Productivity. Store the API token without putting it in shell history:

```sh
python3 scripts/forge-superproductivity.py --forge-home . setup-token
# or: forge superproductivity setup-token
```

Then add this configuration, replacing the IDs with the values returned by the
app:

```yaml
superproductivity:
  enabled: true
  endpoint: http://127.0.0.1:3876
  project_ids:
    Forge: "..."
    CausalDynamics.jl: "..."
```

The adapter talks to the official local REST routes (`/health`, `/projects`,
`/tasks`, `/focus`, `/task-control/stop`). Durations are stored in Super
Productivity as milliseconds and in `TASKS.toml` as whole minutes. Date-only
deadlines use `dueDay`; timed deadlines use `dueWithTime`; planned dates use
`plannedAt`.

## Safe checks

```sh
python3 scripts/forge-superproductivity.py --forge-home . --json status
python3 scripts/forge-superproductivity.py --forge-home . --json doctor
python3 scripts/forge-superproductivity.py --forge-home . --json align
python3 scripts/forge-superproductivity.py --forge-home . --json refresh Forge CausalDynamics.jl
python3 scripts/forge-superproductivity.py --forge-home . --json sync Forge CausalDynamics.jl
```

## Apply (explicit)

One-way import from Super Productivity:

```sh
python3 scripts/forge-superproductivity.py --forge-home . --json refresh --apply Forge CausalDynamics.jl
```

Three-way synchronisation (local ↔ SP ↔ ledger baseline). Conflicts are reported
and left untouched; tasks are never deleted automatically:

```sh
python3 scripts/forge-superproductivity.py --forge-home . --json sync --apply Forge CausalDynamics.jl
```

After cutover, `sync-of-tasks-from-of.py` skips enabled Super Productivity pilot
projects so OmniFocus cannot overwrite them. Prefer **one task backend per
project**. With `nexus.sp_column_mirror: true`, `forge move` mirrors
`Forge/<Column>` tags onto SP tasks (create those tags in SP first; REST cannot
create tags).

## Safety notes

The token is kept in the macOS Keychain under the service
`forge-superproductivity` (on Linux: `secret-tool` or
`~/.config/forge/superproductivity.token`). The adapter refuses non-loopback
endpoints and HTTP redirects, redacts request failures, writes a local ledger at
`.forge/superproductivity.json`, and stores SP identities separately from Forge
task IDs. A Forge identity marker (`<!-- forge:id:... -->`) is maintained in a
narrow portion of SP notes. A missing or stopped app leaves local task files
unchanged. Unsupported SP semantics (waiting/someday export, defer hiding,
recurrence) are reported and excluded rather than approximated.

# OmniFocus plug-ins for Forge

Forge talks to OmniFocus through **Omni Automation (OmniJS)** via JXA
`evaluateJavascript` (see `Sources/ForgeCore/OmniFocus/`). These plug-ins are
optional helpers in OmniFocus’s **Automation** menu.

## Install

1. Open OmniFocus → **Automation** → **Configure Plug-Ins…**
2. Add or link this folder, or copy `ForgeExportInventory.omnijs` into your
   OmniFocus plug-ins directory.
3. Prefer the CLI for day-to-day use:

```bash
# in config.yaml
omnifocus:
  enabled: true

forge omnifocus doctor          # read-only
forge omnifocus align           # dry-run plan (default)
forge omnifocus align --apply   # writes only after confirmation
forge omnifocus refresh         # local .cache snapshot only
```

## Linking convention

Tag OmniFocus tasks under root **`🔥 Forge`** (same string as Finder
`project_tag`) so the final component matches the Finder project folder name
(`🔥 Forge:MyProject`). Configure via `omnifocus.link_tag_root`; older
`Forge:…` tags remain readable via `legacy_link_tag_roots`.

Column mirroring prefers **flat OmniFocus status tags** via `column_tag_aliases`
(e.g. `Coding 🤖`, `Watch 🚧`) when `flat_column_tags` is true (default). Nested
`KanbanStatus/<ColumnName>` remains a fallback / migration target; older
`ForgeColumn/…` tags stay readable. Dry-run consolidation with
`forge omnifocus align --aliases-only`.

When an OmniFocus **project** (same name as the Finder folder) is Done or Dropped,
board Refresh can move that folder to **Shipped** (`sync_completed_project_to_shipped`).

Menubar: **OmniFocus Align…** shows a dry-run plan; **Apply** confirms writes.

## Security

- CLI uses JXA `evaluateJavascript` (Automation permission for your terminal / Forge.app).
- Avoid encoding large scripts in `omnifocus://omnijs-run` URLs for automation
  (Script Security prompts); the plug-in and CLI paths do not require that.

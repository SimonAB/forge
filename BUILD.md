# Building Forge

## If the build seems to stall

A full `swift build` builds the **forge** CLI, which depends on **swift-argument-parser**. That package compiles and can run plugins (`GenerateManual`, `GenerateDoccReference`), which sometimes **stall or run slowly**, especially in Xcode.

**Workarounds:**

- **Build only the apps** (fast, no plugins):
  ```bash
  swift build --target forge-board --target forge-menubar
  ```
  Use this when you’re working on the board or menubar UI. The **forge** CLI won’t be built.

- **Build from Terminal** instead of Xcode; plugin execution is often more reliable there.

- **Full build:** run `swift build` and wait; the first run can take a minute or two while the argument-parser plugins compile and run.

The **build.sh** script builds the app targets first, then the CLI, so the menubar and board apps are available sooner.

Developer flags: `zsh build.sh --no-clean` (skip `swift package clean`) and
`zsh build.sh --no-launch-agent` (skip login agent install).

## Targets

| Target         | Description                    |
|----------------|--------------------------------|
| `forge`        | CLI (board, next, sync, etc.)  |
| `forge-menubar`| Menu bar app (quick capture, sync) |
| `forge-board`  | Standalone board app (Dock, window) |

## Run after building

```bash
# Board app (standalone)
.build/debug/forge-board

# Menubar app
.build/debug/forge-menubar

# CLI
.build/debug/forge board
```

## Tests

```bash
swift test
```

Installer helpers live in **ForgeCore** so the suite does not link Sparkle.
CI runs `swift build`, `swift test`, and `python3 -m py_compile scripts/forge-brief.py`
on pull requests and pushes to `main` (see `.github/workflows/ci.yml`).

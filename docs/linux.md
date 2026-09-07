# Forge on Linux

Forge’s Swift CLI and menu-bar app target **macOS 14+** (Finder tags, AppKit,
OmniFocus, Reminders). This machine runs a **compatible Linux subset**: the same
kanban model, the same tag *bytes*, and Hermes wiring — without the macOS UI.

## What works here

| Feature | Linux |
|---------|--------|
| `config.yaml` + project folders | Yes |
| Kanban column / meta / `#Person` tags | Yes (`forge` Python CLI) |
| `forge board`, `move`, `status`, `project-tag` | Yes |
| Hermes `forge-board` skill + `forge-brief.py` | Yes (once Hermes Agent is installed) |
| Forge.app / Sparkle / OmniFocus / Reminders | macOS only |

## Install on this machine

```bash
# CLI (already linked when set up via the Omarchy agent)
ln -sf ~/Documents/Software/Forge/scripts/linux/forge ~/.local/bin/forge
chmod +x ~/Documents/Software/Forge/scripts/linux/forge

# Adopt existing folders as projects (adds 🔥 Forge + a column tag)
forge adopt ~/Work/apodemus-superspreaders-cdms -c Coding
forge board --list
```

Forge home: `~/Documents/Software/Forge` (`FORGE_HOME` overrides).

## Shared Finder tags (macOS ↔ Linux)

macOS stores tags in the extended attribute:

```text
com.apple.metadata:_kMDItemUserTags
```

as a **binary plist** array of strings — the same format Swift
`FinderTagStore.writeTags` writes.

Linux unprivileged xattrs must live in the `user.` namespace, so the Linux CLI
writes:

```text
user.com.apple.metadata:_kMDItemUserTags
```

with the **identical** binary plist payload. Readers try both names.

### Sidecar (survives sync tools that drop xattrs)

Every write also updates:

```text
<project>/.forge/usertags.bplist
```

If xattrs are missing after a sync, Linux (and a future macOS import helper)
can still recover tags from this file. Prefer enabling xattr sync when your
tool supports it; keep the sidecar as a safety net.

### Sync recommendations

| Method | Notes |
|--------|--------|
| **Syncthing** | Enable **Sync Extended Attributes** on both sides. Syncthing maps Apple ↔ `user.` namespaces across Darwin/Linux. |
| **rsync** | Use `rsync -aX` (preserve xattrs). Test a round-trip before relying on it. |
| **iCloud / many cloud clients** | Often **strip** xattrs. Rely on the `.forge/usertags.bplist` sidecar (and sync that folder). |
| **git** | Does not store xattrs. Commit the sidecar if you want tags in the repo, or keep tags local. |
| **Shared USB / dual-boot** | ext4 stores `user.*` fine; macOS will not read those natively without a bridge — use Syncthing or copy the sidecar. |

### Inspect storage

```bash
forge tags-doctor ~/Work/some-project
getfattr -d ~/Work/some-project
```

### Bringing Linux tags onto a Mac

1. Sync the project folder with xattrs **or** copy `.forge/usertags.bplist`.
2. On the Mac, open the folder in Forge (or re-apply tags). If only the sidecar
   arrived, run (from Forge source on the Mac, once a helper lands):

   ```bash
   # Planned: forge tags import-sidecar <path>
   # Until then, use `xattr -wx` with the bplist bytes, or re-tag in Forge.app
   ```

3. Confirm in Finder → Get Info → Tags.

## Hermes

```bash
# Hermes Agent (not the ollama "hermes" model alias)
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
hermes setup   # point provider at Ollama loopback for privacy
python3 ~/Documents/Software/Forge/scripts/setup-hermes-forge.py
```

The shell alias `hermes` previously launched `ollama launch hermes`; that is
renamed to `hermes-ollama` so Hermes Agent can own `hermes`.

## Tests

```bash
python3 -m unittest discover -s ~/Documents/Software/Forge/Tests/linux -v
```

## Swift port status

`FinderTagStore` now documents and (where compiled) reads both xattr key names.
Full `swift build` on Linux is not required for the Python CLI; AppKit targets
remain macOS-only in `Package.swift`.

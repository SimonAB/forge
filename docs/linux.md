# Forge on Linux

Forge’s Swift menu-bar app targets **macOS 14+** (Finder tags, AppKit,
OmniFocus, Reminders). Linux has a compatible CLI subset and portable kanban
state; the macOS UI remains unchanged.

## What works here

| Feature | Linux |
|---------|--------|
| `config.yaml` + project folders | Yes |
| Kanban column / meta / `#Person` tags | Yes (`forge` Python CLI) |
| Portable `.forge/kanban.toml` | Yes (`forge fs`, opt-in) |
| `forge board`, `move`, `status`, `project-tag` | Yes |
| `forge capture`, `tasks`, `superproductivity` | Yes, with Super Productivity configured |
| Hermes `forge-board` skill + `forge-brief.py` | Yes (once Hermes Agent is installed) |
| Forge.app / Sparkle / OmniFocus / Reminders | macOS only |

## Install on this machine

```bash
# From the Forge checkout on this Linux host.
ln -sf "$(pwd)/scripts/linux/forge" ~/.local/bin/forge
chmod +x scripts/linux/forge

# Adopt existing folders as projects (adds 🔥 Forge + a column tag)
forge adopt ~/Work/apodemus-superspreaders-cdms -c Coding
forge board --list
```

The script uses its checkout as Forge home when it contains `config.yaml` or
`config.sample.yaml`. `FORGE_HOME` (or the older `FORGE_DIR`) overrides it.

## Shared kanban state (macOS ↔ Linux)

Enable the portable Nexus after reviewing its dry run:

```yaml
nexus:
  sidecar_enabled: true
  prefer_sidecar: true
```

```bash
forge fs migrate          # preview sidecars built from local tags
forge fs migrate --apply  # create .forge/kanban.toml
forge fs doctor           # report local-tag / sidecar drift
forge fs sync --apply     # paint local Linux tags from sidecars
```

`.forge/kanban.toml` is the portable representation. It records the workflow
column, configured meta tags, and `#Person` assignees; it is suitable for git,
Dropbox, LocalSend, and filesystems that do not retain xattrs. Migration and
sync are dry-run by default.

## Compatibility xattrs

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

### Legacy Finder bridge

Every Linux write also paints:

```text
user.xdg.tags
```

and preserves the existing Finder-compatible sidecar:

```text
<project>/.forge/usertags.bplist
```

The binary plist exists for compatibility with older Forge folders and direct
Finder-xattr sync. New cross-machine workflows should use `kanban.toml`.

### Sync recommendations

| Method | Notes |
|--------|--------|
| **Syncthing** | Enable **Sync Extended Attributes** on both sides. Syncthing maps Apple ↔ `user.` namespaces across Darwin/Linux. |
| **rsync** | Use `rsync -aX` (preserve xattrs). Test a round-trip before relying on it. |
| **iCloud / many cloud clients** | Often **strip** xattrs. Sync `.forge/kanban.toml`, then run `forge fs sync --apply`. |
| **git** | Does not store xattrs. Commit `.forge/kanban.toml` if kanban state should travel with the project. |
| **Shared USB / dual-boot** | ext4 stores `user.*` fine; sync `.forge/kanban.toml`, then paint each OS’s local tags. |

### Inspect storage

```bash
forge tags-doctor ~/Work/some-project
getfattr -d ~/Work/some-project
```

### Bringing Linux projects onto a Mac

1. Sync the project folder, including `.forge/kanban.toml`.
2. On the Mac, enable the same Nexus settings and run `forge fs sync --apply`.
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

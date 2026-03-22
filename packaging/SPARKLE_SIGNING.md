# Sparkle signing (Forge.app updates)

Forge uses [Sparkle](https://sparkle-project.org/) for in-app updates. The **public** Ed25519 key is in `packaging/sparkle_public_ed25519.key` and is copied into `Info.plist` as `SUPublicEDKey` when assembling `Forge.app`.

## Maintainer setup

1. Install Sparkle release tools (e.g. extract [Sparkle-2.x.x.tar.xz](https://github.com/sparkle-project/Sparkle/releases) and use `bin/generate_keys`).
2. If you need a **new** key pair: run `./bin/generate_keys` and replace the single-line contents of `packaging/sparkle_public_ed25519.key` with the printed `SUPublicEDKey` value.
3. Export the private key for GitHub Actions (one-time per machine):

   ```bash
   ./bin/generate_keys -x /path/to/sparkle_private.key
   ```

4. In the GitHub repository, add a secret **`SPARKLE_EDDSA_PRIVATE_KEY`** whose value is the **entire** contents of that private key file (or pipe the base64 seed as documented by Sparkle).

The **Release** workflow uses this secret with `generate_appcast` to sign update entries and then commits `docs/appcast.xml` to `main`. If the secret is missing, the workflow still uploads release zips but skips the appcast update (and logs a warning).

## Appcast URL

`Forge.app` loads the feed from `SUFeedURL` in `Info.plist` (see `packaging/assemble_forge_app.sh`), currently:

`https://raw.githubusercontent.com/SimonAB/forge/main/docs/appcast.xml`

Forks should change the URL and keys to their own repository and signing material.

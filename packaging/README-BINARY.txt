Forge CLI — macOS binary for Apple Silicon (arm64)
=================================================

Requires macOS 14 or later on a Mac with Apple Silicon. This build is **not**
for Intel Macs — build from source with Xcode / `build.sh` if you need x86_64.

No separate Swift install is needed; the binary uses the system Swift runtime
shipped with recent macOS versions.

Install
-------
1. Unzip this archive.
2. Move the `forge` executable somewhere on your PATH, for example:
     mkdir -p ~/.local/bin
     mv forge ~/.local/bin/
   Ensure ~/.local/bin is listed in your shell PATH.
3. Run: forge --help

If macOS Gatekeeper blocks the binary (“damaged” or unidentified developer),
clear the quarantine attribute from the folder where you extracted it:

     xattr -cr path/to/forge

Full source, Forge.app (menu bar), Intel builds, and the full install script:

     https://github.com/SimonAB/forge

The bundled LICENSE file applies to this software.

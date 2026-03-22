#!/bin/zsh
#
# Assemble Forge.app from a built forge-menubar binary (shared by build.sh and CI).
#
# Usage:
#   packaging/assemble_forge_app.sh <FORGE_DIR> <BIN_DIR> <OUTPUT_APP_PATH>
#
# Arguments:
#   FORGE_DIR      — repository root (reads Sources/ForgeCore/Version.swift)
#   BIN_DIR        — directory containing the `forge-menubar` executable
#   OUTPUT_APP_PATH — full path to the bundle to create (e.g. dist/Forge.app)
#
set -euo pipefail

FORGE_DIR="${1:?FORGE_DIR required}"
BIN_DIR="${2:?BIN_DIR required}"
OUTPUT_APP="${3:?OUTPUT_APP_PATH required}"

MENUBAR_BIN="$BIN_DIR/forge-menubar"
if [[ ! -f "$MENUBAR_BIN" ]]; then
  echo "error: forge-menubar not found at $MENUBAR_BIN" >&2
  exit 1
fi

VERSION_FILE="$FORGE_DIR/Sources/ForgeCore/Version.swift"
if [[ ! -f "$VERSION_FILE" ]]; then
  echo "error: Version.swift not found at $VERSION_FILE" >&2
  exit 1
fi

FORGE_VERSION=$(grep -o 'version = "[^"]*"' "$VERSION_FILE" | cut -d'"' -f2)

CONTENTS="$OUTPUT_APP/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$OUTPUT_APP"
mkdir -p "$MACOS_DIR" "$RESOURCES"

cp "$MENUBAR_BIN" "$MACOS_DIR/Forge"
chmod +x "$MACOS_DIR/Forge"

cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Forge</string>
    <key>CFBundleDisplayName</key>
    <string>Forge</string>
    <key>CFBundleIdentifier</key>
    <string>com.forge.menubar</string>
    <key>CFBundleVersion</key>
    <string>${FORGE_VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${FORGE_VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>Forge</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSRemindersUsageDescription</key>
    <string>Forge syncs tasks with Reminders.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Forge runs commands in your chosen terminal and shows task notifications.</string>
</dict>
</plist>
PLIST

echo "Assembled $OUTPUT_APP (version $FORGE_VERSION)"

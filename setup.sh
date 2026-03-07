#!/bin/zsh
#
# Forge setup script — run this on each Mac to build and install forge.
# The source code syncs via iCloud Drive; this script builds locally.
#
set -e

FORGE_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$HOME/.forge-build"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.forge.menubar.plist"

echo "Forge setup"
echo "==========="
echo "Source:  $FORGE_DIR"
echo "Build:   $BUILD_DIR"
echo ""

# 1. Create local build directory (outside iCloud Drive)
if [ ! -d "$BUILD_DIR" ]; then
    mkdir -p "$BUILD_DIR"
    echo "✓ Created build directory at $BUILD_DIR"
fi

# Ensure .build symlink points to local directory
if [ -d "$FORGE_DIR/.build" ] && [ ! -L "$FORGE_DIR/.build" ]; then
    echo "Moving existing .build out of iCloud Drive..."
    mv "$FORGE_DIR/.build" "$BUILD_DIR.old"
    rsync -a "$BUILD_DIR.old/" "$BUILD_DIR/"
    rm -rf "$BUILD_DIR.old"
fi

if [ ! -L "$FORGE_DIR/.build" ]; then
    ln -s "$BUILD_DIR" "$FORGE_DIR/.build"
    echo "✓ Symlinked .build → $BUILD_DIR"
fi

# 2. Build
echo ""
echo "Building forge..."
cd "$FORGE_DIR"
swift build -c debug 2>&1
BIN_PATH=$(swift build -c debug --show-bin-path)

if [ ! -f "$BIN_PATH/forge" ] || [ ! -f "$BIN_PATH/forge-menubar" ]; then
    echo "Error: build succeeded but forge or forge-menubar binary not found at $BIN_PATH" >&2
    exit 1
fi

echo ""
echo "✓ Build complete"

# 3. Symlink binaries to PATH
if [ -d /opt/homebrew/bin ]; then
    BIN_DIR=/opt/homebrew/bin
elif [ -d /usr/local/bin ]; then
    BIN_DIR=/usr/local/bin
else
    BIN_DIR="$HOME/.local/bin"
    mkdir -p "$BIN_DIR"
fi

ln -sf "$BIN_PATH/forge" "$BIN_DIR/forge"
echo "✓ Symlinked forge → $BIN_DIR/forge"

# 4. Create Forge.app bundle in /Applications
APP_DIR="/Applications/Forge.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

mkdir -p "$MACOS" "$RESOURCES"

cp "$BIN_PATH/forge-menubar" "$MACOS/Forge"

cat > "$CONTENTS/Info.plist" << 'PLIST'
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
    <string>0.4.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.4.0</string>
    <key>CFBundleExecutable</key>
    <string>Forge</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSCalendarsUsageDescription</key>
    <string>Forge syncs tasks with your calendar.</string>
    <key>NSRemindersUsageDescription</key>
    <string>Forge syncs tasks with Reminders.</string>
</dict>
</plist>
PLIST

# Generate the app icon using Pillow (requires: pip3 install Pillow)
if command -v python3 >/dev/null 2>&1 && python3 -c "import PIL" 2>/dev/null; then
    python3 "$FORGE_DIR/generate_icon.py"
    echo "✓ Generated app icon"
else
    echo "⚠ Pillow not installed — skipping icon generation (pip3 install Pillow)"
fi

echo "✓ Installed Forge.app → /Applications/Forge.app"

# 5. Install Launch Agent for auto-start at login
cat > "$LAUNCH_AGENT" << 'LAEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.forge.menubar</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>/Applications/Forge.app</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
LAEOF

launchctl unload "$LAUNCH_AGENT" 2>/dev/null || true
launchctl load "$LAUNCH_AGENT"
echo "✓ Installed Launch Agent (Forge.app starts at login)"

# 6. Verify
echo ""
echo "Verifying..."
forge --version
echo ""
echo "Done. Forge is ready on this Mac."
echo ""
echo "  forge board       — kanban board"
echo "  forge next        — next actions"
echo "  forge sync        — sync with Reminders + Calendar"
echo "  forge review      — weekly review"
echo "  forge --help      — all commands"

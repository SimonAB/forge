#!/bin/zsh
#
# Forge build script — run this on each Mac to build and install Forge.
# The source code syncs via iCloud Drive; this script builds locally.
#
# Flags:
#   --no-clean         Skip `swift package clean` (faster rebuilds)
#   --no-launch-agent  Skip writing/loading the login Launch Agent
#
set -e

FORGE_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$HOME/.forge-build"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.forge.menubar.plist"
DO_CLEAN=1
DO_LAUNCH_AGENT=1

for arg in "$@"; do
    case "$arg" in
        --no-clean) DO_CLEAN=0 ;;
        --no-launch-agent) DO_LAUNCH_AGENT=0 ;;
        -h|--help)
            echo "Usage: zsh build.sh [--no-clean] [--no-launch-agent]"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            echo "Usage: zsh build.sh [--no-clean] [--no-launch-agent]" >&2
            exit 1
            ;;
    esac
done

echo "Forge build"
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

# 2. Check toolchain prerequisites, then build
if ! command -v swift >/dev/null 2>&1; then
    echo "Error: Swift toolchain not found."
    echo "Install Xcode (or the Command Line Tools via 'xcode-select --install') and re-run this script."
    exit 1
fi

echo ""
echo "Building Forge (menubar app and board app first; CLI may take longer due to dependency plugins)..."
cd "$FORGE_DIR"
if [ "$DO_CLEAN" -eq 1 ]; then
    # Clean first so ForgeUI (board backgrounds, tints) and all targets are fully rebuilt
    swift package clean 2>&1 || true
else
    echo "Skipping swift package clean (--no-clean)"
fi
# Single full build so all products (forge, forge-menubar, forge-board) are applied to the output directory
swift build -c debug 2>&1
BIN_PATH=$(swift build -c debug --show-bin-path)

if [ ! -f "$BIN_PATH/forge" ] || [ ! -f "$BIN_PATH/forge-menubar" ]; then
    echo "Error: build succeeded but forge or forge-menubar binary not found at $BIN_PATH" >&2
    exit 1
fi

echo ""
echo "✓ Build complete"

# 3. Generate the app icon (optional, requires Pillow)
# Generate into the local build directory, then bundle it into Forge.app.
if command -v python3 >/dev/null 2>&1 && python3 -c "import PIL" 2>/dev/null; then
    python3 "$FORGE_DIR/generate_icon.py" --output "$BIN_PATH/AppIcon.icns"
    echo "✓ Generated app icon"
else
    echo "⚠ Pillow not installed — skipping icon generation (pip3 install Pillow)"
fi

# 4. Create Forge.app bundle in /Applications (includes embedded forge CLI)
APP_DIR="/Applications/Forge.app"
"$FORGE_DIR/packaging/assemble_forge_app.sh" "$FORGE_DIR" "$BIN_PATH" "$APP_DIR"

echo "✓ Installed Forge.app → /Applications/Forge.app"

# 5. Optional: install Launch Agent for auto-start at login
if [ "$DO_LAUNCH_AGENT" -eq 1 ]; then
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
else
    echo "Skipping Launch Agent (--no-launch-agent)"
fi

# 6. Verify
echo ""
echo "Verifying..."
EMBEDDED_CLI="$APP_DIR/Contents/Resources/bin/forge"
if [ ! -x "$EMBEDDED_CLI" ]; then
    echo "Error: embedded forge CLI is missing or not executable at $EMBEDDED_CLI" >&2
    exit 1
fi
"$EMBEDDED_CLI" --version
echo "Tip: to install the 'forge' CLI on your PATH, open Forge → Preferences → Install CLI…"
echo ""
echo "Done. Forge is ready on this Mac."
echo ""
echo "  Forge.app → Preferences → Install CLI…"

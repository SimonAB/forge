#!/bin/zsh
#
# Package Forge.app for distribution (Developer ID signing + notarisation).
#
# This script is intended for maintainers running on macOS with Xcode installed.
# It assembles Forge.app (including embedded forge CLI), signs it, optionally
# notarises it, and produces a zipped artefact suitable for Sparkle and GitHub Releases.
#
# Usage:
#   packaging/package_forge_app.sh --product release --out dist
#
# Environment:
#   SIGN_IDENTITY            (required) Developer ID Application identity name
#   TEAM_ID                  (optional) Used by notarytool if not configured in keychain profile
#   NOTARY_PROFILE           (optional) notarytool keychain profile name (recommended)
#   NOTARISE                 (optional) set to 1 to notarise + staple
#
set -euo pipefail

FORGE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

CONFIGURATION="release"
OUT_DIR="$FORGE_DIR/dist"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --product)
      CONFIGURATION="${2:?missing value for --product}"
      shift 2
      ;;
    --out)
      OUT_DIR="${2:?missing value for --out}"
      shift 2
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

if [[ "${CONFIGURATION}" != "release" && "${CONFIGURATION}" != "debug" ]]; then
  echo "error: --product must be debug or release (got: ${CONFIGURATION})" >&2
  exit 1
fi

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  echo "error: SIGN_IDENTITY env var is required (Developer ID Application: ...)" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

echo "Building Forge products (${CONFIGURATION})..."
cd "$FORGE_DIR"
swift build -c "$CONFIGURATION" --product forge
swift build -c "$CONFIGURATION" --product forge-menubar

BIN_DIR="$(swift build -c "$CONFIGURATION" --product forge-menubar --show-bin-path)"
APP_DIR="$OUT_DIR/Forge.app"

echo "Assembling Forge.app..."
zsh "$FORGE_DIR/packaging/assemble_forge_app.sh" "$FORGE_DIR" "$BIN_DIR" "$APP_DIR"

echo "Signing Forge.app..."
codesign --force --options runtime --timestamp --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

ZIP_PATH="$OUT_DIR/Forge-macos-arm64.app.zip"
echo "Creating zip: $ZIP_PATH"
rm -f "$ZIP_PATH"
cd "$OUT_DIR"
zip -r -y "$ZIP_PATH" "Forge.app"

if [[ "${NOTARISE:-0}" == "1" ]]; then
  echo "Notarising (this may take a while)..."
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  else
    xcrun notarytool submit "$ZIP_PATH" --wait
  fi
  echo "Stapling notarisation ticket..."
  xcrun stapler staple "$APP_DIR"
fi

echo "Done:"
echo "  App: $APP_DIR"
echo "  Zip: $ZIP_PATH"


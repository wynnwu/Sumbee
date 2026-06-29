#!/usr/bin/env bash
# Build a styled drag-to-Applications .dmg for Sumbee. Requires dist/Sumbee.app first
# (run scripts/bundle.sh). Uses only built-in macOS tools - no third-party deps. The DMG
# is ad-hoc/unsigned, same as the app bundle.
#
# Styling: the window layout (size, icon positions, honeycomb background) lives in a cached
# .DS_Store committed at assets/branding/dmg-DS_Store, so a normal build is FULLY HEADLESS
# (no Finder, no Automation prompt). To regenerate that layout after a design change, delete
# the cache and run this in a Terminal with Finder Automation allowed - it falls back to
# driving Finder via AppleScript and you can re-cache the resulting .DS_Store.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Sumbee"
VOL_NAME="Sumbee"
APP="dist/${APP_NAME}.app"
VERSION="$(grep -E '^VERSION=' scripts/bundle.sh | head -1 | cut -d'"' -f2)"
DMG="dist/${APP_NAME}-${VERSION}.dmg"
BG_SRC="assets/branding/dmg-background.tiff"
BG_NAME="dmg-background.tiff"
DSSTORE_CACHE="assets/branding/dmg-DS_Store"
MOUNT="/Volumes/${VOL_NAME}"

[ -d "$APP" ] || { echo "Missing $APP - run scripts/bundle.sh first" >&2; exit 1; }

# Regenerate the background art if the committed asset is missing.
if [ ! -f "$BG_SRC" ]; then
  echo ">> Rendering DMG background..."
  swift scripts/make-dmg-background.swift /tmp/sumbee-dmg-bg.png 1
  swift scripts/make-dmg-background.swift /tmp/sumbee-dmg-bg@2x.png 2
  tiffutil -cathidpicheck /tmp/sumbee-dmg-bg.png /tmp/sumbee-dmg-bg@2x.png -out "$BG_SRC"
fi

hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true
rm -f "$DMG"

STAGE="$(mktemp -d)"
RW="$(mktemp -u).dmg"
trap 'rm -rf "$STAGE" "$RW"' EXIT

echo ">> Staging..."
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
mkdir "$STAGE/.background"
cp "$BG_SRC" "$STAGE/.background/$BG_NAME"
[ -f "Resources/AppIcon.icns" ] && cp "Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"

USE_CACHE=0
if [ -f "$DSSTORE_CACHE" ]; then
  cp "$DSSTORE_CACHE" "$STAGE/.DS_Store"   # bake the window layout in - no Finder needed
  USE_CACHE=1
fi

echo ">> Creating writable image..."
hdiutil create -srcfolder "$STAGE" -volname "$VOL_NAME" -fs HFS+ -format UDRW -ov "$RW" >/dev/null

echo ">> Finalizing..."
hdiutil attach "$RW" -mountpoint "$MOUNT" -nobrowse -noautoopen >/dev/null
[ -f "$MOUNT/.VolumeIcon.icns" ] && { SetFile -a C "$MOUNT" 2>/dev/null || true; }

if [ "$USE_CACHE" -eq 1 ]; then
  echo "   (styled from cached layout)"
else
  echo ">> Styling window via Finder (no cache present)..."
  osascript <<OSA 2>/dev/null || echo "   (Finder styling skipped - DMG works but is unstyled; run in a Terminal with Finder Automation allowed)"
tell application "Finder"
  tell disk "${VOL_NAME}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {400, 100, 1000, 520}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 12
    set background picture of opts to file ".background:${BG_NAME}"
    set position of item "${APP_NAME}.app" of container window to {150, 200}
    set position of item "Applications" of container window to {450, 200}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
OSA
fi
sync
hdiutil detach "$MOUNT" >/dev/null 2>&1 || hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true

echo ">> Compressing..."
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG" >/dev/null
echo "OK: built $DMG"

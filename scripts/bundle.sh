#!/usr/bin/env bash
# Build a release .app bundle (ad-hoc signed) for local/personal use.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Sumbee"
BUNDLE_ID="com.sumbee.app"
VERSION="0.6.1"
# Incremental build number = git commit count (monotonic, no state file); fallback 1.
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
DIST="dist"
APP="${DIST}/${APP_NAME}.app"

echo ">> Building release..."
swift build -c release

BIN="$(swift build -c release --show-bin-path)/${APP_NAME}"
if [ ! -f "${BIN}" ]; then
  echo "Binary not found at ${BIN}"
  exit 1
fi

# Best-effort icon generation.
if [ ! -f "Resources/AppIcon.icns" ]; then
  echo ">> Generating app icon..."
  ./scripts/make-icon.sh || echo "   (icon generation skipped)"
fi

echo ">> Assembling ${APP}..."
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/${APP_NAME}"

ICON_ENTRY=""
if [ -f "Resources/AppIcon.icns" ]; then
  cp "Resources/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"
  ICON_ENTRY="	<key>CFBundleIconFile</key>
	<string>AppIcon</string>"
fi

cat > "${APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>${APP_NAME}</string>
	<key>CFBundleDisplayName</key>
	<string>${APP_NAME}</string>
	<key>CFBundleExecutable</key>
	<string>${APP_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleVersion</key>
	<string>${BUILD}</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>LSMinimumSystemVersion</key>
	<string>15.0</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.productivity</string>
${ICON_ENTRY}
</dict>
</plist>
PLIST

echo ">> Code signing (ad-hoc)..."
codesign --force --deep --sign - "${APP}" >/dev/null 2>&1 || echo "   (codesign skipped)"

echo "OK: built ${APP}"

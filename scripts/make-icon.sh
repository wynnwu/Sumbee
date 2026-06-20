#!/usr/bin/env bash
# Regenerate Resources/AppIcon.icns from the Sumbee icon source.
# Source of truth: Resources/AppIcon.iconset (PNG sizes 16..1024, incl. @2x).
# Requires macOS `iconutil`. Note: bundle.sh only regenerates when the .icns is
# missing, so the committed icon is normally used as-is.
set -euo pipefail
cd "$(dirname "$0")/.."

ICONSET="Resources/AppIcon.iconset"
if [ ! -d "$ICONSET" ]; then
  echo "Icon source not found: $ICONSET" >&2
  exit 1
fi
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns from $ICONSET"

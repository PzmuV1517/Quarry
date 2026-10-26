#!/bin/bash
# Builds build/Quarry.app. Sign with a stable identity (any "Apple Development" or "Developer ID"
# certificate): macOS ties the Accessibility grant to the signature, and Quarry only loads tools
# signed by the same team.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION=${CONFIGURATION:-release}
swift build -c "$CONFIGURATION"
BIN="$(swift build -c "$CONFIGURATION" --show-bin-path)/Quarry"

APP=build/Quarry.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Quarry"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp catalog.json "$APP/Contents/Resources/catalog.json"

IDENTITY=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ { print $2; exit }')}
if [ -z "$IDENTITY" ]; then
    echo "warning: no signing identity found, signing ad-hoc (Quarry won't be able to load tools)" >&2
    IDENTITY=-
fi
codesign --force --options runtime --sign "$IDENTITY" "$APP"
echo "Built $APP (signed with: $IDENTITY)"

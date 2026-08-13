#!/bin/bash
# Builds MoreCorners.app from the command line (no Xcode needed).
# Usage:
#   ./build.sh          build the app bundle
#   ./build.sh run      build, then (re)launch the app
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME=MoreCorners
CONFIG=release

swift build -c "$CONFIG"

rm -rf "$APP_NAME.app"
mkdir -p "$APP_NAME.app/Contents/MacOS" "$APP_NAME.app/Contents/Resources"
cp ".build/$CONFIG/$APP_NAME" "$APP_NAME.app/Contents/MacOS/"
cp Info.plist "$APP_NAME.app/Contents/"
cp AppIcon.icns "$APP_NAME.app/Contents/Resources/"

# Sign with a stable identity so TCC permissions (Accessibility, Automation)
# survive rebuilds. Preference: $CODESIGN_IDENTITY override, then any Apple
# Development certificate, then ad-hoc as a last resort.
if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
    CODESIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | awk '/Apple Development/ {print $2; exit}')
fi
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    codesign --force --sign "$CODESIGN_IDENTITY" "$APP_NAME.app"
    echo "Built $APP_NAME.app (signed: $CODESIGN_IDENTITY)"
else
    codesign --force --sign - "$APP_NAME.app"
    echo "Built $APP_NAME.app (WARNING: ad-hoc signed — permissions will reset on every rebuild)"
fi

if [[ "${1:-}" == "run" ]]; then
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 0.5
    open "$APP_NAME.app"
    echo "Launched $APP_NAME"
fi

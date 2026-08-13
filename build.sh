#!/bin/bash
# Builds MoreCorners.app from the command line (no Xcode needed).
# Usage:
#   ./build.sh          build the app bundle AND package MoreCorners-<ver>.dmg
#   ./build.sh dmg      same as above (explicit)
#   ./build.sh app      build the app bundle only (no .dmg — faster)
#   ./build.sh run      build, then (re)launch the app (no .dmg)
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

# Package a compressed, drag-to-install .dmg (the app + an /Applications alias).
# Named MoreCorners-<CFBundleShortVersionString>.dmg for tidy GitHub releases.
make_dmg() {
    local version dmg staging
    version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist 2>/dev/null || true)
    if [[ -n "$version" ]]; then dmg="$APP_NAME-$version.dmg"; else dmg="$APP_NAME.dmg"; fi

    staging=$(mktemp -d)
    cp -R "$APP_NAME.app" "$staging/"
    ln -s /Applications "$staging/Applications"

    rm -f "$dmg"
    hdiutil create -volname "$APP_NAME" -srcfolder "$staging" \
        -fs HFS+ -format UDZO -ov -quiet "$dmg"
    rm -rf "$staging"
    echo "Built $dmg"
    # This app is signed with a development (or ad-hoc) certificate, not a
    # Developer ID + notarized, so Gatekeeper will warn on other Macs. Recipients
    # can right-click → Open once, or run: xattr -dr com.apple.quarantine <app>.
    echo "Note: not notarized — see README “Distributing” for the Gatekeeper caveat."
}

case "${1:-dmg}" in
    run)
        pkill -x "$APP_NAME" 2>/dev/null || true
        sleep 0.5
        open "$APP_NAME.app"
        echo "Launched $APP_NAME"
        ;;
    app)
        : # app bundle only — nothing more to do
        ;;
    dmg|"")
        make_dmg
        ;;
    *)
        echo "Usage: ./build.sh [run|app|dmg]" >&2
        exit 1
        ;;
esac

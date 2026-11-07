#!/bin/bash
# Builds a release app and packs it into a versioned zip with a SHA-256 checksum.
# Everything stays local, in dist/release/. Nothing is uploaded or pushed.
#
# The app is ad-hoc signed, not Developer ID signed or notarized, so macOS will
# block it the first time on another Mac. Set ALLOW_DIRTY=1 to package a working
# tree with uncommitted changes (the version then ends in -dirty).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Don't Touch It.app"
STAGING_DIR="$ROOT_DIR/dist/release-build"
RELEASE_DIR="$ROOT_DIR/dist/release"
APP_DIR="$STAGING_DIR/$APP_NAME"

cd "$ROOT_DIR"

if [ "${ALLOW_DIRTY:-0}" != "1" ] && ! git diff --quiet HEAD; then
    echo "error: uncommitted changes in tracked files; commit them or set ALLOW_DIRTY=1" >&2
    exit 1
fi

rm -rf "$STAGING_DIR"
CONFIGURATION=release OUTPUT_DIR="$STAGING_DIR" "$ROOT_DIR/Scripts/build-app.sh"

PLIST="$APP_DIR/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
REVISION="$(/usr/libexec/PlistBuddy -c 'Print :DTIGitRevision' "$PLIST")"
ARCHS="$(lipo -archs "$APP_DIR/Contents/MacOS/DontTouchIt")"

codesign --verify --deep --strict "$APP_DIR"

ZIP_NAME="DontTouchIt-$VERSION-$REVISION.zip"
mkdir -p "$RELEASE_DIR"
rm -f "$RELEASE_DIR/$ZIP_NAME" "$RELEASE_DIR/$ZIP_NAME.sha256"
# ditto keeps the code signature and extended attributes intact; plain zip may not.
ditto -c -k --keepParent "$APP_DIR" "$RELEASE_DIR/$ZIP_NAME"
(cd "$RELEASE_DIR" && shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256")

echo "Packaged: $RELEASE_DIR/$ZIP_NAME"
echo "Checksum: $(cut -d' ' -f1 "$RELEASE_DIR/$ZIP_NAME.sha256")"
echo "Version:  $VERSION ($REVISION), architectures: $ARCHS"
echo "Signing:  ad-hoc, not notarized; macOS will block the first launch on other Macs"

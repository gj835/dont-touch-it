#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Don't Touch It.app"
APP_DIR="$ROOT_DIR/dist/$APP_NAME"

cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-module-cache"
swift build \
    --disable-sandbox \
    --cache-path "$ROOT_DIR/.build/swiftpm-cache" \
    --config-path "$ROOT_DIR/.build/swiftpm-config" \
    --security-path "$ROOT_DIR/.build/swiftpm-security" \
    --scratch-path "$ROOT_DIR/.build" \
    --product DontTouchIt

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$ROOT_DIR/.build/debug/DontTouchIt" "$APP_DIR/Contents/MacOS/DontTouchIt"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>DontTouchIt</string>
    <key>CFBundleIdentifier</key>
    <string>com.dont-touch-it.app</string>
    <key>CFBundleName</key>
    <string>Don't Touch It</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>27.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# Keep the code-signing identifier stable so macOS TCC permissions continue to
# identify rebuilt local app bundles as the same application.
codesign --force --deep --sign - \
    --identifier com.dont-touch-it.app \
    -r='designated => identifier "com.dont-touch-it.app"' \
    "$APP_DIR"

echo "Built: $APP_DIR"

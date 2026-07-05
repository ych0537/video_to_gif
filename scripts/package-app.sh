#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_NAME="Video2GIF"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_FILE="$RESOURCES_DIR/Video2GIF.icns"
BUNDLED_FFMPEG="$ROOT_DIR/Vendor/ffmpeg/arm64/bin/ffmpeg"

cd "$ROOT_DIR"
swift build -c release --product VideoToGifApp

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_DIR/VideoToGifApp" "$MACOS_DIR/$APP_NAME"
swift "$ROOT_DIR/scripts/generate-icon.swift" "$ICON_FILE"

if [[ -x "$BUNDLED_FFMPEG" ]]; then
  cp "$BUNDLED_FFMPEG" "$RESOURCES_DIR/ffmpeg"
  chmod +x "$RESOURCES_DIR/ffmpeg"
else
  echo "Warning: bundled ffmpeg not found at $BUNDLED_FFMPEG"
  echo "Run scripts/build-ffmpeg-arm64.sh to include ffmpeg in the app."
fi

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>Video2GIF</string>
  <key>CFBundleIdentifier</key>
  <string>local.video2gif.app</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Video2GIF</string>
  <key>CFBundleDisplayName</key>
  <string>Video2GIF</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>Video2GIF</string>
  <key>CFBundleIconName</key>
  <string>Video2GIF</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

chmod +x "$MACOS_DIR/$APP_NAME"
xattr -cr "$APP_DIR" 2>/dev/null || true
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "Built: $APP_DIR"

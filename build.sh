#!/bin/bash
# Builds build/Fan Control.app (release). Usage: ./build.sh [--install]  (--install copies it to /Applications)
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Fan Control.app"
VERSION="1.0"

swift build -c release --product FanControl
swift build -c release --product FanHelper
BIN="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/FanControl" "$APP/Contents/MacOS/FanControl"
cp "$BIN/FanHelper" "$APP/Contents/MacOS/fanhelper"

if [ ! -f build/AppIcon.icns ]; then
  swift scripts/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Fan Control</string>
  <key>CFBundleDisplayName</key><string>Fan Control</string>
  <key>CFBundleIdentifier</key><string>com.fancontrol.app</string>
  <key>CFBundleExecutable</key><string>FanControl</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Menu bar fan &amp; temperature control</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP/Contents/MacOS/fanhelper"
codesign --force --sign - "$APP"
echo "Built $APP"

# Keep macOS from treating the build copy as "the" app (it would become the login item target).
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -u "$PWD/$APP" 2>/dev/null || true

if [ "${1:-}" = "--install" ]; then
  # Quit gracefully so the app hands the fans back to Auto, then wait for it to exit.
  if pgrep -x FanControl >/dev/null; then
    osascript -e 'tell application id "com.fancontrol.app" to quit' 2>/dev/null || true
    for _ in {1..20}; do pgrep -x FanControl >/dev/null || break; sleep 0.25; done
    pkill -x FanControl 2>/dev/null || true
    REOPEN=1
  fi
  rm -rf "/Applications/Fan Control.app"
  cp -R "$APP" /Applications/
  "$LSREGISTER" -f "/Applications/Fan Control.app"
  echo "Installed to /Applications/Fan Control.app"
  [ "${REOPEN:-0}" = 1 ] && open "/Applications/Fan Control.app"
fi

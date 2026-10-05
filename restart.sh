#!/usr/bin/env bash
set -euo pipefail
TIME_IT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIME_IT_CONFIGURATION="${TIME_IT_BUILD_CONFIGURATION:-debug}"
TIME_IT_APP="$HOME/Applications/Time It.app"
swift build --package-path "$TIME_IT_ROOT" -c "$TIME_IT_CONFIGURATION"
TIME_IT_BIN="$(swift build --package-path "$TIME_IT_ROOT" -c "$TIME_IT_CONFIGURATION" --show-bin-path)/time-it-app"
TIME_IT_STAGE="$(mktemp -d)/Time It.app"
mkdir -p "$TIME_IT_STAGE/Contents/MacOS" "$TIME_IT_STAGE/Contents/Resources"
cp "$TIME_IT_BIN" "$TIME_IT_STAGE/Contents/MacOS/time-it-app"
cp "$TIME_IT_ROOT/icons/time-it.png" "$TIME_IT_STAGE/Contents/Resources/TimeIt.png"
cat > "$TIME_IT_STAGE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.mikerosoft.time-it</string>
<key>CFBundleName</key><string>Time It</string>
<key>CFBundleDisplayName</key><string>Time It</string>
<key>CFBundleExecutable</key><string>time-it-app</string>
<key>CFBundleIconFile</key><string>TimeIt.png</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleURLTypes</key><array><dict>
<key>CFBundleURLName</key><string>com.mikerosoft.time-it.commands</string>
<key>CFBundleURLSchemes</key><array><string>time-it</string></array>
</dict></array>
</dict></plist>
PLIST
TIME_IT_IDENTITY="${TIME_IT_CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -n 1)}"
codesign --force --timestamp=none --sign "${TIME_IT_IDENTITY:--}" --requirements '=designated => identifier "com.mikerosoft.time-it"' "$TIME_IT_STAGE"
if pgrep -f "$TIME_IT_APP/Contents/MacOS/time-it-app" >/dev/null; then
  pkill -TERM -f "$TIME_IT_APP/Contents/MacOS/time-it-app"
  for TIME_IT_WAIT in {1..30}; do
    if ! pgrep -f "$TIME_IT_APP/Contents/MacOS/time-it-app" >/dev/null; then break; fi
    sleep 0.1
  done
  if pgrep -f "$TIME_IT_APP/Contents/MacOS/time-it-app" >/dev/null; then
    echo 'Time It is still running. Close it before installing.' >&2
    exit 1
  fi
fi
mkdir -p "$HOME/Applications"
if [ -e "$TIME_IT_APP" ]; then
  TIME_IT_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$TIME_IT_APP/Contents/Info.plist")"
  if [ "$TIME_IT_BUNDLE_ID" != 'com.mikerosoft.time-it' ]; then
    echo 'An unrelated Time It.app exists. Move it before installing.' >&2
    exit 1
  fi
  rm -rf "$TIME_IT_APP"
fi
mv "$TIME_IT_STAGE" "$TIME_IT_APP"
rmdir "$(dirname "$TIME_IT_STAGE")"
open "$TIME_IT_APP"
echo "Installed $TIME_IT_APP"

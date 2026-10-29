#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="dist/Snapgrok.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/Snapgrok" "$APP/Contents/MacOS/Snapgrok"
cp "Packaging/Info.plist" "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp "Packaging/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)"
if [[ -n "$IDENTITY" ]]; then
  codesign --force --sign "$IDENTITY" --identifier local.snapgrok --timestamp=none "$APP"
else
  codesign --force --sign - "$APP"
fi
echo "Built $APP"

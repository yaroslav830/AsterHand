#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/PocketCodex.app
sdk_path="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos clang \
  -arch arm64 -miphoneos-version-min=16.0 -isysroot "$sdk_path" \
  -O2 -Wall -Wextra -ISources -c Sources/PCProcess.c -o build/PCProcess.o
xcrun --sdk iphoneos clang \
  -arch arm64 -miphoneos-version-min=16.0 -isysroot "$sdk_path" \
  -fobjc-arc -fblocks -O2 -Wall -Wextra -Wno-unused-parameter -ISources \
  Sources/*.m build/PCProcess.o \
  -framework Foundation -framework UIKit -framework Security -framework CoreGraphics -framework WebKit \
  -Wl,-headerpad,0x1000 -o build/PocketCodex.app/PocketCodex
python3 scripts/sync_localizations.py
cp -R Resources/*.lproj build/PocketCodex.app/
cp Resources/Info.plist Resources/localizations.json Resources/user-guide.json Resources/tools.json build/PocketCodex.app/
cp -R Resources/Guide build/PocketCodex.app/
codesign --force --sign - --entitlements entitlements.plist --timestamp=none build/PocketCodex.app
codesign --verify --strict build/PocketCodex.app
python3 scripts/package_app.py
python3 scripts/verify_artifact.py

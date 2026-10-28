#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" .build/native
TARGET="$(uname -m)-apple-macosx13.0"
xcrun swiftc -O -whole-module-optimization -parse-as-library -emit-object -emit-module \
  -module-name ZoomiesCore -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  -target "$TARGET" Sources/ZoomiesCore/*.swift \
  -emit-module-path .build/native/ZoomiesCore.swiftmodule -o .build/native/ZoomiesCore.o
# Stage outside synced folders: File Provider can inject Finder flags into an
# .app after signing. The ZIP keeps the signed bundle intact for installation.
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/LokiDotZoomies.XXXXXX")"
APP="$STAGING/LokiDot Zoomies.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -O -module-cache-path "$CLANG_MODULE_CACHE_PATH" -target "$TARGET" \
  -I .build/native Sources/LokiDotZoomies/*.swift .build/native/ZoomiesCore.o \
  -o "$APP/Contents/MacOS/LokiDotZoomies"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Artwork is explicitly supplied by its owner and is never part of public Git.
SPRITESHEET="${LOKIDOT_SPRITESHEET:-$PWD/local-assets/LokiSpriteSheet.png}"
if [[ -f "$SPRITESHEET" ]]; then
  cp "$SPRITESHEET" "$APP/Contents/Resources/LokiSpriteSheet.png"
fi
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
mkdir -p dist
ditto -c -k --keepParent "$APP" "$PWD/dist/LokiDot Zoomies.zip"
printf '%s\n' "$APP" > dist/app-path.txt
printf 'Built %s\n' "$APP"

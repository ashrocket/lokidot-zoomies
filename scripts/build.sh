#!/bin/bash
set -euo pipefail
PACK=""
if [[ $# -ne 0 ]]; then
  if [[ $# -ne 2 || "$1" != "--pack" ]]; then
    echo "Usage: ./scripts/build.sh [--pack /path/to/pack-folder]" >&2
    exit 2
  fi
  PACK="$(cd -- "$2" && pwd)"
fi
if [[ -n "${LOKIDOT_SPRITESHEET:-}" ]]; then
  echo "LOKIDOT_SPRITESHEET was replaced by --pack. Add manifest.json; see docs/sprite-packs.md." >&2
  exit 2
fi
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${LOKIDOT_MODULE_CACHE:-$HOME/Library/Caches/LokiDotZoomies/ModuleCache}"
TARGET="$(uname -m)-apple-macosx13.0"
# Stage outside synced folders: File Provider can inject Finder flags into an
# .app after signing, or change source metadata during compilation.
# The ZIP keeps the signed bundle intact for installation.
BUILD_ROOT="${LOKIDOT_BUILD_ROOT:-$HOME/Library/Caches/LokiDotZoomies/Builds}"
mkdir -p "$BUILD_ROOT"
STAGING="$(mktemp -d "$BUILD_ROOT/build.XXXXXX")"
cp -R Sources "$STAGING/Sources"
NATIVE="$STAGING/native"
LOKIDOT_SOURCE_ROOT="$STAGING" LOKIDOT_WORK_ROOT="$STAGING" ./scripts/compile-core.sh
if [[ -n "$PACK" ]]; then "$NATIVE/SpritePackTool" validate "$PACK"; fi
APP="$STAGING/LokiDot Zoomies.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -O -module-cache-path "$CLANG_MODULE_CACHE_PATH" -target "$TARGET" \
  -I "$NATIVE" "$STAGING"/Sources/LokiDotZoomies/*.swift "$NATIVE/ZoomiesCore.o" \
  -o "$APP/Contents/MacOS/LokiDotZoomies"
xcrun swiftc -O -module-cache-path "$CLANG_MODULE_CACHE_PATH" -target "$TARGET" \
  -I "$NATIVE" "$STAGING/Sources/LokiDotCLI/main.swift" "$NATIVE/ZoomiesCore.o" \
  -o "$APP/Contents/MacOS/lokidot"
cp "$NATIVE/SpritePackTool" "$APP/Contents/MacOS/SpritePackTool"
cp scripts/install.sh "$APP/Contents/Resources/install.sh"
cp Resources/DogSetupPrompt.txt "$APP/Contents/Resources/DogSetupPrompt.txt"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -n "$PACK" ]]; then
  "$NATIVE/SpritePackTool" bundle "$PACK" "$APP"
fi
# Only ready defaults are packaged. Never copy an entire input folder.
for DEFAULT_PACK in Resources/Characters/*; do
  [[ -d "$DEFAULT_PACK" ]] || continue
  "$NATIVE/SpritePackTool" copy "$DEFAULT_PACK" "$APP/Contents/Resources/Characters/$(basename "$DEFAULT_PACK")"
done
codesign --force --sign - "$APP/Contents/MacOS/lokidot"
codesign --force --sign - "$APP/Contents/MacOS/SpritePackTool"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
mkdir -p dist
ditto -c -k --keepParent "$APP" "$PWD/dist/LokiDot Zoomies.zip"
printf '%s\n' "$APP" > dist/app-path.txt
printf 'Built %s\nOpen: ./lokidot\nInstall app + command: ./lokidot install --no-build\nTry the whole pack: ./lokidot all\n' "$APP"

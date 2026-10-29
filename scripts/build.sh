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
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
TARGET="$(uname -m)-apple-macosx13.0"
./scripts/compile-core.sh
if [[ -n "$PACK" ]]; then .build/native/SpritePackTool validate "$PACK"; fi
# Stage outside synced folders: File Provider can inject Finder flags into an
# .app after signing. The ZIP keeps the signed bundle intact for installation.
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/LokiDotZoomies.XXXXXX")"
APP="$STAGING/LokiDot Zoomies.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -O -module-cache-path "$CLANG_MODULE_CACHE_PATH" -target "$TARGET" \
  -I .build/native Sources/LokiDotZoomies/*.swift .build/native/ZoomiesCore.o \
  -o "$APP/Contents/MacOS/LokiDotZoomies"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -n "$PACK" ]]; then
  .build/native/SpritePackTool bundle "$PACK" "$APP"
fi
# Only ready defaults are packaged. Never copy an entire input folder.
for DEFAULT_PACK in Resources/Characters/*; do
  [[ -d "$DEFAULT_PACK" ]] || continue
  .build/native/SpritePackTool copy "$DEFAULT_PACK" "$APP/Contents/Resources/Characters/$(basename "$DEFAULT_PACK")"
done
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
mkdir -p dist
ditto -c -k --keepParent "$APP" "$PWD/dist/LokiDot Zoomies.zip"
printf '%s\n' "$APP" > dist/app-path.txt
printf 'Built %s\nThis does not open or replace a running pet.\n' "$APP"

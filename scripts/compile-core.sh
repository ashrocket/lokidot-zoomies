#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${LOKIDOT_MODULE_CACHE:-$HOME/Library/Caches/LokiDotZoomies/ModuleCache}"
WORK_ROOT="${LOKIDOT_WORK_ROOT:-$PWD/.build}"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$WORK_ROOT/native"
TARGET="$(uname -m)-apple-macosx13.0"
SOURCE_ROOT="${LOKIDOT_SOURCE_ROOT:-$PWD}"
xcrun swiftc -O -whole-module-optimization -parse-as-library -emit-object -emit-module \
  -module-name ZoomiesCore -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  -target "$TARGET" "$SOURCE_ROOT"/Sources/ZoomiesCore/*.swift \
  -emit-module-path "$WORK_ROOT/native/ZoomiesCore.swiftmodule" -o "$WORK_ROOT/native/ZoomiesCore.o"
xcrun swiftc -O -module-cache-path "$CLANG_MODULE_CACHE_PATH" -target "$TARGET" \
  -I "$WORK_ROOT/native" "$SOURCE_ROOT/Sources/SpritePackTool/main.swift" "$WORK_ROOT/native/ZoomiesCore.o" \
  -o "$WORK_ROOT/native/SpritePackTool"

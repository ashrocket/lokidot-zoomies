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
xcrun swiftc -O -module-cache-path "$CLANG_MODULE_CACHE_PATH" -target "$TARGET" \
  -I .build/native Sources/SpritePackTool/main.swift .build/native/ZoomiesCore.o \
  -o .build/native/SpritePackTool

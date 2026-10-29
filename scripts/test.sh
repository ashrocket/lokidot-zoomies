#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${LOKIDOT_MODULE_CACHE:-$HOME/Library/Caches/LokiDotZoomies/ModuleCache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
# Keep compiler inputs stable when the checkout is in a synced Documents folder.
SNAPSHOT="$(mktemp -d "${TMPDIR:-/tmp}/LokiDot-tests.XXXXXX")"
trap 'rm -rf "$SNAPSHOT"' EXIT
cp -R Sources/ZoomiesCore Tests/ZoomiesCoreTests "$SNAPSHOT/"
cp scripts/TestRunner.swift "$SNAPSHOT/TestRunner.swift"
mkdir -p "$SNAPSHOT/build"
DEVELOPER_FRAMEWORKS="$(xcrun --show-sdk-platform-path)/Developer/Library/Frameworks"
DEVELOPER_LIBRARIES="$(xcrun --show-sdk-platform-path)/Developer/usr/lib"
XCODE_FRAMEWORKS="$(xcode-select -p)/../SharedFrameworks"
xcrun swiftc -enable-testing -whole-module-optimization -parse-as-library -emit-object -emit-module \
  -module-name ZoomiesCore -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  "$SNAPSHOT"/ZoomiesCore/*.swift \
  -emit-module-path "$SNAPSHOT/build/ZoomiesCore.swiftmodule" -o "$SNAPSHOT/build/ZoomiesCore.o"
xcrun swiftc -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  -I "$SNAPSHOT/build" -I "$DEVELOPER_LIBRARIES" -L "$DEVELOPER_LIBRARIES" -F "$DEVELOPER_FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$DEVELOPER_FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$DEVELOPER_LIBRARIES" \
  -Xlinker -rpath -Xlinker "$XCODE_FRAMEWORKS" \
  "$SNAPSHOT"/ZoomiesCoreTests/*.swift "$SNAPSHOT/TestRunner.swift" "$SNAPSHOT/build/ZoomiesCore.o" \
  -o "$SNAPSHOT/build/MotionTests"
"$SNAPSHOT/build/MotionTests"

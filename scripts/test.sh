#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" .build/tests
DEVELOPER_FRAMEWORKS="$(xcrun --show-sdk-platform-path)/Developer/Library/Frameworks"
DEVELOPER_LIBRARIES="$(xcrun --show-sdk-platform-path)/Developer/usr/lib"
XCODE_FRAMEWORKS="$(xcode-select -p)/../SharedFrameworks"
xcrun swiftc -enable-testing -parse-as-library -emit-object -emit-module \
  -module-name ZoomiesCore -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  Sources/ZoomiesCore/MotionRoute.swift \
  -emit-module-path .build/tests/ZoomiesCore.swiftmodule -o .build/tests/ZoomiesCore.o
xcrun swiftc -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  -I .build/tests -I "$DEVELOPER_LIBRARIES" -L "$DEVELOPER_LIBRARIES" -F "$DEVELOPER_FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$DEVELOPER_FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$DEVELOPER_LIBRARIES" \
  -Xlinker -rpath -Xlinker "$XCODE_FRAMEWORKS" \
  Tests/ZoomiesCoreTests/*.swift scripts/TestRunner.swift .build/tests/ZoomiesCore.o \
  -o .build/tests/MotionTests
.build/tests/MotionTests

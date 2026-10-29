#!/bin/bash
set -euo pipefail
if [[ $# -ne 1 ]]; then
  echo "Usage: ./scripts/make-sample-pack.sh NEW_FOLDER" >&2
  exit 2
fi
case "$1" in /*) DESTINATION="$1";; *) DESTINATION="$PWD/$1";; esac
cd "$(dirname "$0")/.."
./scripts/compile-core.sh
exec .build/native/SpritePackTool sample "$DESTINATION"

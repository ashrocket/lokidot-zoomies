#!/bin/bash
set -euo pipefail
if [[ $# -ne 1 ]]; then
  echo "Usage: ./scripts/validate-pack.sh /path/to/pack-folder" >&2
  exit 2
fi
PACK="$(cd -- "$1" && pwd)"
cd "$(dirname "$0")/.."
./scripts/compile-core.sh
exec .build/native/SpritePackTool validate "$PACK"

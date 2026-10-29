#!/bin/bash
set -euo pipefail
RUN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$RUN_ROOT/scripts/build.sh" "$@"
open "$(cat "$RUN_ROOT/dist/app-path.txt")"

#!/bin/bash
set -euo pipefail
RUN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "$RUN_ROOT/lokidot" "$@"
